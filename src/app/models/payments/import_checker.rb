module Payments
  # Conferência da importação de pagamentos ou de estornos (R48 a R56, R60 a R63): lê o arquivo, valida linha a linha, grava na preparação,
  # aplica as regras de unicidade e simula o efeito sobre a carteira, sem gravar nada nela. É processamento em lote em segundo plano (decisão 0021),
  # em etapas retomáveis (`ActiveJob::Continuable`): leitura (cursor = última linha gravada, lotes de `Staging.batch_size` linhas, um commit por lote),
  # regras de unicidade (cada fatia é uma transação e não se repete), ordem do fluxo e simulação (que só lê: se for interrompida, recomeça do início da
  # etapa, sem deixar nada na carteira) e resumo. As regras são Ruby sobre modelos; o SQL que sobra aqui só lê. Idempotente: uma conferência nova (ou
  # repetida) recomeça do zero, porque a etapa `prepare` limpa a preparação.
  class ImportChecker
    Sql = Portfolio::Sql

    # `runner` roda as etapas: o job (com cursor e retomada) ou o `InlineRunner` (seguido, na mesma chamada).
    def run(import, runner = Portfolio::InlineRunner)
      runner.step(:prepare) { prepare(import) }
      runner.step(:read, start: 1) { |step| read(import, step) }
      runner.step(:rules) { apply_rules(import) }
      runner.step(:order) { PaymentStream.prepare(import) }
      runner.step(:simulate) { simulate(import) }
      runner.step(:summary) { finish(import) }
    rescue Portfolio::ImportRefused => error
      refuse(import, error)
    end

    # Falha inesperada (o job esgotou as tentativas): a preparação some e a importação fica como falha, sem conferência.
    def fail!(import, error)
      Rails.error.report(error, handled: true, context: { import_id: import.id })
      clean(import)
      import.update!(status: :failed, failure_reason: error.class.name.demodulize, finished_at: Time.current, progress_label: nil)
    end

    private
      def prepare(import)
        import.update!(status: :checking, progress_percent: 1, progress_label: "Lendo o arquivo")
        clean(import)
      end

      def clean(import)
        [ PaymentRow, ImportRejection ].each { |model| model.where(import_id: import.id).delete_all }
      end

      def refuse(import, error)
        clean(import)
        import.update!(status: :rejected, failure_reason: error.message, finished_at: Time.current, progress_percent: 100, progress_label: nil)
        FileUtils.rm_f(import.file_path)
      end

      # Etapa de leitura: valida as linhas e grava a preparação e as recusas em lotes. O cursor é a última linha do arquivo já gravada.
      def read(import, step)
        kind = import.kind
        file = Portfolio::CsvFile.new(import.file_path.to_s, required: SheetModel.required(kind), optional: SheetModel.optional(kind))
        validator = import.reversals? ? ReversalRowValidator.new : PaymentRowValidator.new
        discard_after(import, step.cursor) if step.resumed?
        staging = Staging.new(import.id)
        total = [ File.size(import.file_path) / 80, 1 ].max
        lines = 0
        rejected = []
        last = step.cursor

        file.each_row do |csv_row|
          lines += 1
          next if csv_row.line <= step.cursor

          parsed, reason = validator.validate(csv_row)
          if parsed
            staging.add(parsed)
          else
            rejected << { import_id: import.id, line: csv_row.line, reason: reason }
          end
          last = csv_row.line
          next unless staging.full?

          save_batch(staging, rejected)
          step.set!(last)
          import.update!(progress_percent: [ 50, 1 + (49 * lines / total) ].min, progress_label: "Lendo o arquivo: #{number(lines)} linhas")
        end
        save_batch(staging, rejected)
        step.set!(last)
        import.update!(summary: { lines: lines, blank_lines: file.blank_lines, ignored_columns: file.ignored_columns })
      end

      # Um lote vai todo ou não vai: preparação e recusas na mesma transação.
      def save_batch(staging, rejected)
        return if staging.size.zero? && rejected.empty?

        ApplicationRecord.transaction do
          staging.flush
          ImportRejection.insert_all!(rejected) unless rejected.empty?
        end
        rejected.clear
      end

      # Retomada: o que passou do cursor (gravado, mas sem o cursor avançar) sai, e a leitura refaz a partir dali.
      def discard_after(import, cursor)
        [ PaymentRow, ImportRejection ].each { |model| model.where(import_id: import.id).where("line > ?", cursor).delete_all }
      end

      def apply_rules(import)
        reversals = import.reversals?
        # Tabela recém-carregada não tem estatísticas: sem ANALYZE o planejador subestima o tamanho e escolhe plano ruim.
        ActiveRecord::Base.connection.execute("analyze payment_rows")
        import.update!(progress_percent: 55, progress_label: "Conferindo canais e repetições")
        reject_unknown_channels(import, reversals)
        reject_repeated(import, reversals)
        mark_already_registered(import, reversals)
        reject_reversal_problems(import) if reversals
        import.update!(progress_percent: 70, progress_label: "Ordenando o fluxo")
      end

      # Marca as linhas como recusadas (ou ignoradas) e registra o motivo; cada fatia é uma transação. `reasons`: linha => motivo.
      def reject(import, reasons, ignored: false)
        reasons.each_slice(1000) do |slice|
          ApplicationRecord.transaction do
            ImportRejection.insert_all!(slice.map { |line, reason| { import_id: import.id, line: line, reason: reason, ignored: ignored } })
            PaymentRow.where(import_id: import.id, line: slice.map(&:first)).update_all(ignored ? { ok: false, registered: true } : { ok: false })
          end
        end
      end

      # R49: canal não cadastrado ou desativado (no estorno, canal desativado é aceito: revisão 5).
      def reject_unknown_channels(import, reversals)
        channels = PaymentChannel.where(tenant_id: import.tenant_id)
        codes = (reversals ? channels : channels.where(active: true)).pluck(:code)
        reject(import, PaymentRow.where(import_id: import.id, ok: true).where.not(channel_code: codes).order(:line).pluck(:line).index_with { "canal não cadastrado ou desativado" })
      end

      # R48 e R61: o repetido no mesmo arquivo é recusado; vale a primeira ocorrência.
      def reject_repeated(import, reversals)
        label = reversals ? "estorno repetido na linha " : "pagamento repetido na linha "
        repeated = Sql.rows(<<~SQL, import.id)
          select line, first_line from (
            select line, first_value(line) over w as first_line, row_number() over w as rn
            from payment_rows where import_id = ? and ok
            window w as (partition by channel_code, identifier order by line)) d where rn > 1
        SQL
        reject(import, repeated.to_h { |row| [ row["line"].to_i, "#{label}#{row['first_line']}" ] })
      end

      # R48 e R61: já registrado numa importação anterior: a linha é ignorada, sem efeito, e aparece na lista como ignorada (não é recusa).
      def mark_already_registered(import, reversals)
        table = reversals ? "payment_reversals" : "payments"
        label = reversals ? "estorno já registrado, ignorado" : "pagamento já registrado, ignorado"
        lines = Sql.rows(<<~SQL, import.tenant_id, import.tenant_id, import.id).map { |row| row["line"].to_i }
          select r.line from payment_rows r join payment_channels ch on ch.tenant_id = ? and ch.code = r.channel_code
          join #{table} x on x.tenant_id = ? and x.channel_id = ch.id and x.identifier = r.identifier
          where r.import_id = ? and r.ok
        SQL
        reject(import, lines.index_with { label }, ignored: true)
      end

      # R61: pagamento não encontrado no canal; data anterior ao pagamento; título de cliente anonimizado; valor maior que o saldo estornável.
      def reject_reversal_problems(import)
        t = import.tenant_id
        i = import.id
        found = "from payment_rows r join payment_channels ch on ch.tenant_id = ? and ch.code = r.channel_code"
        match = "p.tenant_id = ? and p.channel_id = ch.id and p.identifier = r.payment_identifier"
        lines = ->(sql, *binds) { Sql.rows(sql, *binds).map { |row| row["line"].to_i } }

        reject(import, lines.call("select r.line #{found} where r.import_id = ? and r.ok and not exists (select 1 from payments p where #{match})", t, i, t).index_with { "pagamento não encontrado no canal" })
        reject(import, lines.call("select r.line #{found} join payments p on #{match} where r.import_id = ? and r.ok and r.paid_on < p.paid_on", t, t, i)
                          .index_with { "data do estorno anterior ao pagamento" })

        # 07, revisão 5: estorno de título de cliente anonimizado é recusado quando todos os clientes do contrato estão anonimizados; com um
        # cliente ainda identificável o estorno segue. Consulta: `contract_customers (contract_id, customer_id)`.
        anonymized = <<~SQL
          join bills b on b.id = p.bill_id
          where r.import_id = ? and r.ok and exists (select 1 from contract_customers cc where cc.contract_id = b.contract_id)
            and not exists (select 1 from contract_customers cc join customers cu on cu.id = cc.customer_id where cc.contract_id = b.contract_id and cu.anonymized_at is null)
        SQL
        reject(import, lines.call("select r.line #{found} join payments p on #{match} #{anonymized}", t, t, i).index_with { "título de cliente anonimizado" })

        # Valor acima do que ainda não foi estornado do pagamento, somando as linhas do próprio arquivo em ordem.
        over = Sql.rows(<<~SQL, t, t, i)
          select x.line, x.reversible - (x.cum - x.amount_cents) as left_cents from (
            select r.line, r.amount_cents, p.amount_cents - p.reversed_cents as reversible,
                   sum(r.amount_cents) over (partition by p.id order by r.paid_on, r.line) as cum
            from payment_rows r join payment_channels ch on ch.tenant_id = ? and ch.code = r.channel_code
            join payments p on p.tenant_id = ? and p.channel_id = ch.id and p.identifier = r.payment_identifier
            where r.import_id = ? and r.ok) x where x.cum > x.reversible
        SQL
        reject(import, over.to_h { |row| [ row["line"].to_i, "valor maior que o saldo estornável de R$ #{Money.format([ row['left_cents'].to_i, 0 ].max)}" ] })
      end

      # A simulação só lê: o efeito que a confirmação vai gravar, com os mesmos números. O fluxo da simulação fica na memória.
      def simulate(import)
        import.update!(progress_percent: 75, progress_label: "Simulando o efeito na carteira")
        effect = import.reversals? ? ReversalProcessor.new.run(import, commit: false) : Processor.new.run(import, commit: false)
        import.update!(summary: import.summary_data.merge(effect: effect))
      end

      def finish(import)
        file_data = import.summary_data
        id = import.id
        accepted = PaymentRow.where(import_id: id, ok: true, pending_payment_id: nil)
        amount = accepted.sum(:amount_cents)
        summary = { lines: file_data[:lines], valid: accepted.count, rejected: ImportRejection.where(import_id: id, ignored: false).count,
                    ignored: ImportRejection.where(import_id: id, ignored: true).count, blank_lines: file_data[:blank_lines], ignored_columns: file_data[:ignored_columns],
                    amount_cents: amount, amount_formatted: Money.format(amount), effect: file_data[:effect] }
        import.update!(status: :checked, summary: summary, checked_at: Time.current, progress_percent: 100, progress_label: nil)
      end

      def number(value) = value.to_s.reverse.scan(/\d{1,3}/).join(".").reverse
  end
end
