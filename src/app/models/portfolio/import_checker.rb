module Portfolio
  # Conferência da importação (R10): lê o arquivo, valida linha a linha, grava na tabela de preparação e compara com a carteira.
  # Nada toca a carteira: só a preparação, as recusas e o resumo da importação. É processamento em lote em segundo plano (decisão 0021), em
  # etapas retomáveis (`ActiveJob::Continuable`): leitura (cursor = última linha gravada, lotes de `Staging.batch_size` linhas, um commit por lote),
  # repetições, resumo. As regras são Ruby sobre modelos; o SQL que sobra aqui só lê (contagens e junções do resumo). Idempotente: uma conferência
  # nova (ou repetida) recomeça do zero, porque a etapa `preparar` limpa a preparação.
  class ImportChecker
    def initialize(validator: RowValidator.new)
      @validator = validator
    end

    # `runner` roda as etapas: o job (com cursor e retomada) ou o `InlineRunner` (seguido, na mesma chamada).
    def run(import, runner = InlineRunner)
      runner.step(:prepare) { prepare(import) }
      runner.step(:read, start: 1) { |step| read(import, step) }
      runner.step(:repeats) { find_repeats(import) }
      runner.step(:summary) { finish(import) }
    rescue ImportRefused => error
      refuse(import, error)
    end

    # Falha inesperada (o job esgotou as tentativas): a preparação some e a importação fica como falha, sem conferência.
    def fail!(import, error)
      clean(import)
      import.update!(status: :failed, failure_reason: error.class.name.demodulize, finished_at: Time.current, progress_label: nil)
    end

    private
      def prepare(import)
        import.update!(status: :checking, progress_percent: 1, progress_label: "Lendo o arquivo")
        clean(import)
      end

      def clean(import)
        [ ImportRow, ImportRejection, ImportContact, ImportWarning ].each { |model| model.where(import_id: import.id).delete_all }
      end

      def refuse(import, error)
        clean(import)
        import.update!(status: :rejected, failure_reason: error.message, finished_at: Time.current, progress_percent: 100, progress_label: nil)
        FileUtils.rm_f(import.file_path)
      end

      # Etapa de leitura: valida as linhas e grava a preparação, as recusas e os avisos em lotes. O cursor é a última linha do arquivo já gravada.
      def read(import, step)
        file = CsvFile.new(import.file_path.to_s)
        discard_after(import, step.cursor) if step.resumed?
        staging = Staging.new(import.id)
        total = [ File.size(import.file_path) / 90, 1 ].max
        lines = 0
        rejected = []
        warned = []
        tenant = import.tenant
        tenant_keys = { "phone" => tenant.phone_key, "email" => tenant.email_key }
        last = step.cursor

        file.each_row do |csv_row|
          lines += 1
          next if csv_row.line <= step.cursor

          parsed, reason = @validator.validate(csv_row)
          if parsed
            staging.add(parsed, FoldedText.fold(parsed.name))
            (parsed.warnings + staging.add_contacts(parsed, tenant_keys)).each { |warning| warned << { import_id: import.id, line: csv_row.line, reason: warning } }
          else
            rejected << { import_id: import.id, line: csv_row.line, reason: reason }
            # Mantém a chave do título para ele não ser retirado no batimento (R15).
            document = Document.normalize(csv_row.values["documento"])
            staging.add_key_only(csv_row.line, document, csv_row.values["titulo"].to_s[0, 100]) if Document.problem(csv_row.values["documento"]).nil? && csv_row.values["titulo"].present?
          end
          last = csv_row.line
          next unless staging.full?

          save_batch(staging, rejected, warned)
          step.set!(last)
          import.update!(progress_percent: [ 60, 1 + (59 * lines / total) ].min, progress_label: "Lendo o arquivo: #{number(lines)} linhas")
        end
        save_batch(staging, rejected, warned)
        step.set!(last)
        # O que o resumo precisa do arquivo e que só se sabe depois de lê-lo inteiro.
        import.update!(summary: { lines: lines, blank_lines: file.blank_lines, ignored_columns: file.ignored_columns })
      end

      # Um lote vai todo ou não vai: preparação, contatos, recusas e avisos na mesma transação.
      def save_batch(staging, rejected, warned)
        return if staging.size.zero? && rejected.empty? && warned.empty?

        ApplicationRecord.transaction do
          staging.flush
          ImportRejection.insert_all!(rejected) unless rejected.empty?
          ImportWarning.insert_all!(warned) unless warned.empty?
        end
        rejected.clear
        warned.clear
      end

      # Retomada: o que passou do cursor (gravado, mas sem o cursor avançar) sai, e a leitura refaz a partir dali.
      def discard_after(import, cursor)
        [ ImportRow, ImportContact, ImportRejection, ImportWarning ].each { |model| model.where(import_id: import.id).where("line > ?", cursor).delete_all }
      end

      # Repetições no arquivo: nomes divergentes (R7) e título repetido (R4). Cada fatia é uma transação e não se repete se a etapa for retomada.
      def find_repeats(import)
        # Tabela recém-carregada não tem estatísticas: sem ANALYZE o planejador subestima o tamanho e escolhe plano ruim.
        ActiveRecord::Base.connection.execute("analyze import_rows")
        ActiveRecord::Base.connection.execute("analyze import_contacts")
        import.update!(progress_percent: 65, progress_label: "Procurando repetições e nomes divergentes")
        reject_divergent_names(import)
        reject_duplicate_bills(import)
        # Os contatos das linhas recusadas (nomes divergentes, título repetido) não entram: saem da preparação aqui, uma vez, e a confirmação
        # não precisa juntar de novo com as linhas aceitas.
        ImportContact.where(import_id: import.id, line: ImportRow.where(import_id: import.id, ok: false).select(:line)).delete_all
        import.update!(progress_percent: 80, progress_label: "Comparando com a carteira")
      end

      # R7: nomes diferentes para o mesmo documento no arquivo: todas as linhas do documento são recusadas.
      def reject_divergent_names(import)
        rows = ImportRow.where(import_id: import.id, ok: true)
        rows.group(:document).having("count(distinct name_key) > 1").pluck(:document).each_slice(500) do |documents|
          firsts = rows.where(document: documents).group(:document, :name_key).minimum(:line).group_by { |(document, _), _| document }
          lines = rows.where(document: documents).pluck(:document, :line).group_by(&:first)
          rejections = lines.flat_map do |document, pairs|
            reason = "nomes diferentes para o mesmo documento: linhas #{join_lines(firsts.fetch(document).map(&:last).sort)}"
            pairs.map { |(_, line)| { import_id: import.id, line: line, reason: reason } }
          end
          ApplicationRecord.transaction do
            ImportRejection.insert_all!(rejections)
            ImportRow.where(import_id: import.id, document: documents).update_all(ok: false, keep_document: true)
          end
        end
      end

      # R4: o mesmo título repetido no arquivo: a primeira ocorrência vale e as seguintes são recusadas.
      def reject_duplicate_bills(import)
        rows = ImportRow.where(import_id: import.id, ok: true)
        rows.group(:document).having("count(*) <> count(distinct number)").pluck(:document).each_slice(500) do |documents|
          first_line = {}
          repeated = rows.where(document: documents).order(:line).pluck(:document, :number, :line).filter_map do |document, number, line|
            first = first_line[[ document, number ]]
            first_line[[ document, number ]] ||= line
            [ line, first ] if first
          end
          next if repeated.empty?

          ApplicationRecord.transaction do
            ImportRejection.insert_all!(repeated.map { |line, first| { import_id: import.id, line: line, reason: "título repetido na linha #{first}" } })
            ImportRow.where(import_id: import.id, line: repeated.map(&:first)).update_all(ok: false)
          end
        end
      end

      def finish(import)
        file_data = import.summary_data
        summary = summarize(import, file_data)
        import.update!(status: :checked, summary: summary, checked_at: Time.current, progress_percent: 100, progress_label: nil)
      end

      def summarize(import, file_data)
        tenant_id = import.tenant_id
        id = import.id
        ok = Sql.one("select count(*) as bills, count(distinct document) as customers, coalesce(sum(amount_cents), 0) as amount from import_rows where import_id = ? and ok", id)
        existing = Sql.one(<<~SQL, tenant_id, tenant_id, id)
          select
            count(*) filter (where b.id is null) as bills_new,
            count(*) filter (where b.id is not null and b.status = 'active' and
              (b.amount_cents <> r.amount_cents or b.due_date <> r.due_date or b.description is distinct from r.description or
               coalesce(k.code, '') <> coalesce(r.contract, ''))) as bills_updated,
            count(*) filter (where b.id is not null and b.status = 'active' and
              b.amount_cents = r.amount_cents and b.due_date = r.due_date and b.description is not distinct from r.description and
              coalesce(k.code, '') = coalesce(r.contract, '')) as bills_unchanged,
            count(*) filter (where b.status = 'withdrawn') as bills_reincluded,
            count(*) filter (where b.status = 'paid') as bills_paid_kept
          from import_rows r
          left join customers c on c.tenant_id = ? and c.document = r.document
          left join bills b on b.tenant_id = ? and b.customer_id = c.id and b.number = r.number
          left join contracts k on k.id = b.contract_id
          where r.import_id = ? and r.ok
        SQL
        new_customers = Sql.one(<<~SQL, id, tenant_id)["n"]
          select count(*) as n from (select distinct document from import_rows where import_id = ? and ok) d
          where not exists (select 1 from customers c where c.tenant_id = ? and c.document = d.document)
        SQL

        withdraw = { count: 0, amount_cents: 0 }
        kept = 0
        if import.full_sync?
          row = Sql.one(<<~SQL, tenant_id, id)
            select count(*) as n, coalesce(sum(b.amount_cents), 0) as amount
            from bills b join customers c on c.id = b.customer_id
            where b.tenant_id = ? and b.status = 'active' and not exists (
              select 1 from import_rows r where r.import_id = ? and r.document = c.document and (r.number = b.number or r.keep_document))
          SQL
          withdraw = { count: row["n"].to_i, amount_cents: row["amount"].to_i }
          # R15: título gravado cuja linha foi recusada não é retirado.
          kept = Sql.one(<<~SQL, tenant_id, id, id)["n"]
            select count(*) as n from bills b join customers c on c.id = b.customer_id
            where b.tenant_id = ? and b.status = 'active' and exists (
              select 1 from import_rows r where r.import_id = ? and not r.ok and r.document = c.document and (r.number = b.number or r.keep_document))
              and not exists (select 1 from import_rows r where r.import_id = ? and r.ok and r.document = c.document and r.number = b.number)
          SQL
        end
        omitted = Sql.one("select count(distinct document) as n from import_rows where import_id = ? and ok and contract is null", id)["n"]
        # R9b: contratos com mais de um cliente na carga e linhas que declaram papel.
        multi_customer = Sql.one(<<~SQL, id)["n"]
          select count(*) as n from (select contract from import_rows where import_id = ? and ok and contract is not null
                                     group by contract having count(distinct document) > 1) t
        SQL
        roles_declared = Sql.one("select count(*) as n from import_rows where import_id = ? and ok and roles is not null", id)["n"]

        setting = TenantSetting.find_by!(tenant_id: tenant_id)
        policy = setting.discrepancy_policy
        reported = surcharges_reported(id)

        { lines: file_data[:lines], valid: ok["bills"].to_i, discrepancy_policy: policy, correction_policy: setting.correction_policy, kept_by_tenant: kept_by_tenant(tenant_id, id),
          contact_warnings: ImportWarning.where(import_id: id).count, contacts: Sql.one("select count(*) as n from import_contacts where import_id = ?", id)["n"].to_i, discrepancies: discrepancies(tenant_id, id, policy), reported_surcharges: reported, surcharge_comparison: (Charges::SurchargeComparison.before(import) if setting.surcharge_comparison_policy_before?), rejected: ImportRejection.where(import_id: id).count, blank_lines: file_data[:blank_lines],
          ignored_columns: file_data[:ignored_columns], customers: ok["customers"].to_i, customers_new: new_customers.to_i, amount_cents: ok["amount"].to_i,
          bills_new: existing["bills_new"].to_i, bills_updated: existing["bills_updated"].to_i, bills_unchanged: existing["bills_unchanged"].to_i,
          bills_reincluded: existing["bills_reincluded"].to_i, bills_paid_kept: existing["bills_paid_kept"].to_i, to_withdraw: withdraw,
          kept_by_rejection: kept.to_i, contracts_created_by_omission: omitted.to_i, contracts_multi_customer: multi_customer.to_i,
          roles_declared: roles_declared.to_i, amount_formatted: Money.format(ok["amount"].to_i) }
      end

      # R98: os títulos com pagamento cujo valor muda, com o efeito pela política do credor da importação; o total e as primeiras linhas (a
      # tela mostra até 200). O mesmo cálculo da confirmação (`DiscrepancyRules`). Consulta: `bills (tenant_id, customer_id, number)`.
      def discrepancies(tenant_id, import_id, policy)
        reported = "r.amount_cents"
        base = <<~SQL
          from import_rows r
          join customers c on c.tenant_id = #{tenant_id.to_i} and c.document = r.document
          join bills b on b.tenant_id = #{tenant_id.to_i} and b.customer_id = c.id and b.number = r.number
          where r.import_id = ? and r.ok and b.amount_cents <> r.amount_cents and #{DiscrepancyRules::WITH_ALLOCATION}
        SQL
        count = Sql.one("select count(*) as n #{base}", import_id)["n"].to_i
        items = Sql.rows(<<~SQL, import_id).map do |row|
          select b.number, c.name as customer, b.amount_cents as previous_cents, r.amount_cents as reported_cents, b.paid_cents as allocated_cents,
                 #{DiscrepancyRules.balance_before_sql} as balance_before_cents, #{DiscrepancyRules.balance_after_sql(policy, reported)} as balance_after_cents,
                 #{DiscrepancyRules.excess_sql(policy, reported)} as excess_cents, #{DiscrepancyRules.effect_sql(policy, reported)} as effect
          #{base} order by c.name, b.number limit 200
        SQL
          row.slice("number", "customer", "effect").merge(row.slice("previous_cents", "reported_cents", "allocated_cents", "balance_before_cents",
                                                                    "balance_after_cents", "excess_cents").transform_values(&:to_i))
        end
        { count: count, items: items }
      end

      # R102: o total informado pelo credor em cada componente (só para conferência).
      def surcharges_reported(import_id)
        row = Sql.one(<<~SQL, import_id)
          select count(*) filter (where penalty_cents is not null or interest_cents is not null or correction_cents is not null or other_cents is not null) as lines,
                 coalesce(sum(penalty_cents), 0) as penalty_cents, coalesce(sum(interest_cents), 0) as interest_cents,
                 coalesce(sum(correction_cents), 0) as correction_cents, coalesce(sum(other_cents), 0) as other_cents
          from import_rows where import_id = ? and ok
        SQL
        row.transform_values(&:to_i)
      end

      # R118: o que a carga queria mudar em dados mantidos pelo credor (nome marcado e diferente; contato inválido ou "não perturbe" que
      # voltaria a válido), com o total e as primeiras linhas; o efeito depende da política (`correction_policy`, guardada no resumo).
      # Consultas: `customers (tenant_id, document)` e `customer_contacts (customer_id, kind, key)`.
      def kept_by_tenant(tenant_id, import_id)
        names_from = <<~SQL
          from (select distinct on (document) document, name from import_rows where import_id = ? and ok order by document, line desc) n
          join customers c on c.tenant_id = ? and c.document = n.document where c.name_kept and c.name is distinct from n.name
        SQL
        contacts_from = <<~SQL
          from import_contacts ic
          join customers c on c.tenant_id = ? and c.document = ic.document
          join customer_contacts k on k.customer_id = c.id and k.kind = ic.kind and k.key = ic.key
          where ic.import_id = ? and k.status <> 'valid' and not ic.tenant_contact
        SQL
        {
          names: { count: Sql.one("select count(*) as n #{names_from}", import_id, tenant_id)["n"].to_i,
                   items: Sql.rows("select c.name as current_name, n.name as load_name #{names_from} order by c.name limit 50", import_id, tenant_id).map(&:symbolize_keys) },
          contacts: { count: Sql.one("select count(distinct k.id) as n #{contacts_from}", tenant_id, import_id)["n"].to_i,
                      items: Sql.rows("select c.name as customer, k.kind, k.value, k.status #{contacts_from} group by k.id, c.name order by c.name limit 50", tenant_id, import_id).map(&:symbolize_keys) }
        }
      end

      def join_lines(lines)
        return lines.first.to_s if lines.size <= 1

        "#{lines[0...-1].join(', ')} e #{lines.last}"
      end

      def number(value) = value.to_s.reverse.scan(/\d{1,3}/).join(".").reverse
  end
end
