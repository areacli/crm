module Portfolio
  # Confirmação da importação (R10): grava só as linhas válidas na carteira. É processamento em lote em segundo plano (decisão 0021): Active
  # Record sobre os modelos de domínio, com validações, callbacks e a auditoria de sempre (`Change.record!`, com a importação e o usuário), em etapas
  # retomáveis (`ActiveJob::Continuable`). Cada lote de clientes (`customers_per_batch`) é uma transação, e o cursor avança depois do commit, então uma
  # interrupção deixa a carteira com clientes inteiros: gravados por completo ou não gravados. A confirmação é idempotente por cliente e título,
  # e uma etapa repetida não duplica nada. Enquanto roda, a importação fica "confirmando" e só vira "confirmada" no fim.
  class ImportConfirmer
    # Clientes por lote da carteira e títulos por lote da retirada: cada lote é uma transação e um ponto de retomada. Atributos de classe para os
    # testes de retomada usarem lotes de um cliente.
    class_attribute :customers_per_batch, instance_writer: false, default: 500
    class_attribute :withdrawals_per_batch, instance_writer: false, default: 1000

    # `runner` roda as etapas: o job (com cursor e retomada) ou o `InlineRunner` (seguido, na mesma chamada).
    def run(import, runner = InlineRunner)
      runner.step(:prepare) { prepare(import) }
      runner.step(:portfolio, start: "") { |step| write_portfolio(import, step) }
      runner.step(:withdrawals, start: 0) { |step| withdraw_absent(import, step) } if import.full_sync?
      runner.step(:finish) { finish(import) }
    end

    # Falha definitiva: o que os lotes já gravaram fica (clientes inteiros); a mesma carga, enviada de novo, conclui o que falta (idempotente).
    def fail!(import, error)
      Rails.error.report(error, handled: true, context: { import_id: import.id })
      [ ImportRow, ImportContact ].each { |model| model.where(import_id: import.id).delete_all }
      import.update!(status: :failed, failure_reason: error.class.name.demodulize, finished_at: Time.current, progress_label: nil)
    end

    private
      def prepare(import)
        import.update!(status: :confirming, progress_percent: 1, progress_label: "Gravando a carteira")
      end

      # Clientes em ordem de documento, `customers_per_batch` por vez; o cursor é o último documento gravado.
      def write_portfolio(import, step)
        accepted = ImportRow.where(import_id: import.id, ok: true)
        total = accepted.distinct.count(:document)
        done = step.cursor.empty? ? 0 : accepted.where(document: ..step.cursor).distinct.count(:document)
        batch = ConfirmBatch.new(import)
        loop do
          documents = accepted.where("document > ?", step.cursor).distinct.order(:document).limit(self.class.customers_per_batch).pluck(:document)
          break if documents.empty?

          ApplicationRecord.transaction { batch.call(documents) }
          done += documents.size
          step.set!(documents.last)
          import.update!(progress_percent: 1 + (73 * done / total), progress_label: "Gravando a carteira: #{number(done)} de #{number(total)} clientes")
        end
      end

      # R11 e R14: no batimento, o título ativo que não está no arquivo passa a retirado, sem motivo atribuído. O cursor é o último título examinado.
      # O batimento é por sistema (17, R414): só os títulos do sistema da importação são examinados; os dos outros sistemas e os do CRM ficam como
      # estão. A passagem é pela chave primária, em ordem de id, com o sistema como filtro (como já era com o credor).
      def withdraw_absent(import, step)
        import.update!(progress_percent: 75, progress_label: "Retirando títulos ausentes")
        own_id = import.source_system.key_own_id?
        loop do
          bills = Bill.where(tenant_id: import.tenant_id, source_system_id: import.source_system_id, status: "active", kind: "common").where("bills.id > ?", step.cursor)
                      .order(:id).limit(self.class.withdrawals_per_batch).includes(:customer).to_a
          break if bills.empty?

          ApplicationRecord.transaction { withdraw(import, bills, own_id) }
          step.set!(bills.last.id)
        end
      end

      # O título veio no arquivo quando há linha dele, aceita ou recusada (R15): em chave natural, pelo documento e número; em id próprio, pelo id do
      # título (`import_rows (import_id, external_bill_id)`). O documento com nomes divergentes guarda todos os títulos dele (R7).
      def withdraw(import, bills, own_id)
        staged = ImportRow.where(import_id: import.id)
        by_document = staged.where(document: bills.map { |bill| bill.customer.document }.uniq).pluck(:document, :number, :keep_document)
        kept_documents = by_document.filter_map { |document, _, keep| document if keep }.to_set
        present = if own_id then staged.where(external_bill_id: bills.map(&:external_id)).pluck(:external_bill_id).to_set
        else by_document.to_set { |document, number, _| [ document, number ] }
        end
        now = Time.current
        changes = bills.filter_map do |bill|
          document = bill.customer.document
          next if present.include?(own_id ? bill.external_id : [ document, bill.number ]) || kept_documents.include?(document)

          bill.update!(status: "withdrawn", withdrawn_at: now, withdrawn_import_id: import.id)
          [ bill, "withdrawn", { field: "status", before: "active", after: "withdrawn" } ]
        end
        Change.record_many!(changes, tenant_id: import.tenant_id, actor: import.user, import: import)
      end

      def finish(import)
        import.update!(progress_percent: 95, progress_label: "Concluindo")
        # 10, R202 e R202a: título retirado ou passado a outro contrato sai das promessas dele (SQL de conjunto, a migrar na parte 2 da revisão).
        Promises::BillExit.run(import.tenant_id)
        Agreements::BillExit.run(import.tenant_id)
        # Carga em massa deixa as estatísticas defasadas (o autovacuum demora): sem isto, a primeira consulta depois da carga pega um plano ruim.
        %w[customers customer_contacts contracts contract_customers bills].each { |table| ActiveRecord::Base.connection.execute("analyze #{table}") }
        [ ImportRow, ImportContact ].each { |model| model.where(import_id: import.id).delete_all }
        FileUtils.rm_f(import.file_path) if import.stored_path
        import.update!(status: :confirmed, progress_percent: 100, progress_label: nil, finished_at: Time.current)
      end

      def number(value) = value.to_s.reverse.scan(/\d{1,3}/).join(".").reverse
  end
end
