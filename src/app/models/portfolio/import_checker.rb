module Portfolio
  # Conferência da importação (R10): lê o arquivo, valida linha a linha, grava na tabela de preparação e compara com a carteira.
  # Nada toca a carteira: só a preparação, as recusas e o resumo da importação. Idempotente: recomeça do zero se for repetida.
  class ImportChecker
    PROGRESS_EVERY = 5000

    def initialize(validator: RowValidator.new)
      @validator = validator
    end

    def run(import)
      import.update!(status: :checking, progress_percent: 1, progress_label: "Lendo o arquivo")
      clean(import)
      begin
        summary = check(import)
      rescue ImportRefused => error
        clean(import)
        import.update!(status: :rejected, failure_reason: error.message, finished_at: Time.current, progress_percent: 100, progress_label: nil)
        FileUtils.rm_f(import.file_path)
        return
      end
      import.update!(status: :checked, summary: summary, checked_at: Time.current, progress_percent: 100, progress_label: nil)
    end

    private
      def clean(import)
        Sql.run("delete from import_rows where import_id = ?", import.id)
        Sql.run("delete from import_rejections where import_id = ?", import.id)
      end

      def check(import)
        file = CsvFile.new(import.file_path.to_s)
        staging = Staging.new(import.id)
        total = [ File.size(import.file_path) / 90, 1 ].max
        lines = 0
        rejected = []

        file.each_row do |csv_row|
          lines += 1
          parsed, reason = @validator.validate(csv_row)
          if parsed
            staging.add(parsed, FoldedText.fold(parsed.name))
          else
            rejected << { import_id: import.id, line: csv_row.line, reason: reason }
            # Mantém a chave do título para ele não ser retirado no batimento (R15).
            document = Document.normalize(csv_row.values["documento"])
            staging.add_key_only(csv_row.line, document, csv_row.values["titulo"].to_s[0, 100]) if Document.problem(csv_row.values["documento"]).nil? && csv_row.values["titulo"].present?
          end
          next unless (lines % PROGRESS_EVERY).zero?

          import.update!(progress_percent: [ 60, 1 + (59 * lines / total) ].min, progress_label: "Lendo o arquivo: #{number(lines)} linhas")
        end
        staging.flush
        # Tabela recém-carregada não tem estatísticas: sem ANALYZE o planejador subestima o tamanho e escolhe plano ruim.
        Sql.connection.execute("analyze import_rows")
        rejected.each_slice(2000) { |chunk| ImportRejection.insert_all(chunk) }

        import.update!(progress_percent: 65, progress_label: "Procurando repetições e nomes divergentes")
        reject_divergent_names(import)
        reject_duplicate_bills(import)
        import.update!(progress_percent: 80, progress_label: "Comparando com a carteira")
        summarize(import, file, lines)
      end

      # R7: nomes diferentes para o mesmo documento no arquivo: todas as linhas do documento são recusadas.
      def reject_divergent_names(import)
        bad = Sql.rows(<<~SQL, import.id)
          select document, array_to_string(array_agg(first_line order by first_line), ',') as firsts
          from (select document, name_key, min(line) as first_line from import_rows where import_id = ? and ok group by document, name_key) t
          group by document having count(*) > 1
        SQL
        bad.each_slice(500) do |chunk|
          pairs = chunk.map { |row| [ row["document"], "nomes diferentes para o mesmo documento: linhas #{join_lines(row['firsts'].split(','))}" ] }
          values = pairs.map { |document, reason| "(#{Sql.connection.quote(document)}, #{Sql.connection.quote(reason)})" }.join(",")
          Sql.run(<<~SQL, import.id)
            insert into import_rejections (import_id, line, reason)
            select r.import_id, r.line, m.reason from import_rows r join (values #{values}) as m(document, reason) on m.document = r.document
            where r.import_id = ? and r.ok
          SQL
          Sql.run("update import_rows set ok = false, keep_document = true where import_id = ? and document in (?)", import.id, pairs.map(&:first))
        end
      end

      # R4: o mesmo título repetido no arquivo: a primeira ocorrência vale e as seguintes são recusadas.
      def reject_duplicate_bills(import)
        Sql.run(<<~SQL, import.id)
          insert into import_rejections (import_id, line, reason)
          select import_id, line, 'título repetido na linha ' || first_line
          from (select import_id, line, first_value(line) over w as first_line, row_number() over w as rn
                from import_rows where import_id = ? and ok
                window w as (partition by import_id, document, number order by line)) d where rn > 1
        SQL
        Sql.run(<<~SQL, import.id, import.id)
          update import_rows r set ok = false
          from (select line from (select line, row_number() over (partition by document, number order by line) as rn
                                  from import_rows where import_id = ? and ok) d where rn > 1) dup
          where r.import_id = ? and r.line = dup.line
        SQL
      end

      def summarize(import, file, lines)
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

        { lines: lines, valid: ok["bills"].to_i, rejected: ImportRejection.where(import_id: id).count, blank_lines: file.blank_lines,
          ignored_columns: file.ignored_columns, customers: ok["customers"].to_i, customers_new: new_customers.to_i, amount_cents: ok["amount"].to_i,
          bills_new: existing["bills_new"].to_i, bills_updated: existing["bills_updated"].to_i, bills_unchanged: existing["bills_unchanged"].to_i,
          bills_reincluded: existing["bills_reincluded"].to_i, bills_paid_kept: existing["bills_paid_kept"].to_i, to_withdraw: withdraw,
          kept_by_rejection: kept.to_i, contracts_created_by_omission: omitted.to_i, contracts_multi_customer: multi_customer.to_i,
          roles_declared: roles_declared.to_i, amount_formatted: Money.format(ok["amount"].to_i) }
      end

      def join_lines(lines)
        return lines.first.to_s if lines.size <= 1

        "#{lines[0...-1].join(', ')} e #{lines.last}"
      end

      def number(value) = value.to_s.reverse.scan(/\d{1,3}/).join(".").reverse
  end
end
