module Payments
  # Conferência da importação de pagamentos ou de estornos (R48 a R56, R60 a R63): lê o arquivo, valida linha a linha, grava na preparação,
  # aplica as regras de unicidade e simula o efeito sobre a carteira, sem gravar nada nela. A confirmação refaz a mesma simulação, numa
  # única transação, e grava. Idempotente: se for repetida, recomeça do zero.
  class ImportChecker
    PROGRESS_EVERY = 5000

    Sql = Portfolio::Sql

    def run(import)
      import.update!(status: :checking, progress_percent: 1, progress_label: "Lendo o arquivo")
      clean(import)
      begin
        summary = check(import)
      rescue Portfolio::ImportRefused => error
        clean(import)
        import.update!(status: :rejected, failure_reason: error.message, finished_at: Time.current, progress_percent: 100, progress_label: nil)
        FileUtils.rm_f(import.file_path)
        return
      end
      import.update!(status: :checked, summary: summary, checked_at: Time.current, progress_percent: 100, progress_label: nil)
    end

    private
      def clean(import)
        Sql.run("delete from payment_rows where import_id = ?", import.id)
        Sql.run("delete from import_rejections where import_id = ?", import.id)
      end

      def check(import)
        reversals = import.reversals?
        kind = import.kind
        file = Portfolio::CsvFile.new(import.file_path.to_s, required: SheetModel.required(kind), optional: SheetModel.optional(kind))
        validator = reversals ? ReversalRowValidator.new : PaymentRowValidator.new
        staging = Staging.new(import.id)
        total = [ File.size(import.file_path) / 80, 1 ].max
        lines = 0
        rejected = []

        file.each_row do |csv_row|
          lines += 1
          parsed, reason = validator.validate(csv_row)
          if parsed
            staging.add(parsed)
          else
            rejected << { import_id: import.id, line: csv_row.line, reason: reason }
          end
          next unless (lines % PROGRESS_EVERY).zero?

          import.update!(progress_percent: [ 50, 1 + (49 * lines / total) ].min, progress_label: "Lendo o arquivo: #{number(lines)} linhas")
        end
        staging.flush
        # Tabela recém-carregada não tem estatísticas: sem ANALYZE o planejador subestima o tamanho e escolhe plano ruim.
        Sql.connection.execute("analyze payment_rows")
        rejected.each_slice(2000) { |chunk| ImportRejection.insert_all(chunk) }

        import.update!(progress_percent: 55, progress_label: "Conferindo canais e repetições")
        reject_unknown_channels(import, reversals)
        reject_repeated(import, reversals)
        mark_already_registered(import, reversals)
        reject_reversal_problems(import) if reversals

        import.update!(progress_percent: 75, progress_label: "Simulando o efeito na carteira")
        # O fluxo da simulação é uma tabela temporária que vive até o fim da transação.
        ApplicationRecord.transaction do
          effect = reversals ? ReversalProcessor.new.run(import, commit: false) : Processor.new.run(import, commit: false)
          summarize(import, file, lines, effect)
        end
      end

      # R49: canal não cadastrado ou desativado (no estorno, canal desativado é aceito: revisão 5).
      def reject_unknown_channels(import, reversals)
        active = reversals ? "" : " and ch.active"
        where = "r.import_id = ? and r.ok and not exists (select 1 from payment_channels ch where ch.tenant_id = ? and ch.code = r.channel_code#{active})"
        Sql.run("insert into import_rejections (import_id, line, reason) select r.import_id, r.line, 'canal não cadastrado ou desativado' from payment_rows r where #{where}",
                import.id, import.tenant_id)
        Sql.run("update payment_rows r set ok = false where #{where}", import.id, import.tenant_id)
      end

      # R48 e R61: o repetido no mesmo arquivo é recusado; vale a primeira ocorrência.
      def reject_repeated(import, reversals)
        label = reversals ? "estorno repetido na linha " : "pagamento repetido na linha "
        Sql.run(<<~SQL, label, import.id)
          insert into import_rejections (import_id, line, reason)
          select import_id, line, ? || first_line from (
            select import_id, line, first_value(line) over w as first_line, row_number() over w as rn
            from payment_rows where import_id = ? and ok
            window w as (partition by channel_code, identifier order by line)) d where rn > 1
        SQL
        Sql.run(<<~SQL, import.id, import.id)
          update payment_rows r set ok = false from (
            select line from (select line, row_number() over (partition by channel_code, identifier order by line) as rn
                              from payment_rows where import_id = ? and ok) d where rn > 1) dup
          where r.import_id = ? and r.line = dup.line
        SQL
      end

      # R48 e R61: já registrado numa importação anterior: a linha é ignorada, sem efeito, e aparece na lista como ignorada (não é recusa).
      def mark_already_registered(import, reversals)
        table = reversals ? "payment_reversals" : "payments"
        label = reversals ? "estorno já registrado, ignorado" : "pagamento já registrado, ignorado"
        join = <<~SQL
          from payment_rows r join payment_channels ch on ch.tenant_id = :t and ch.code = r.channel_code
          join #{table} x on x.tenant_id = :t and x.channel_id = ch.id and x.identifier = r.identifier
          where r.import_id = :i and r.ok
        SQL
        binds = { t: import.tenant_id, i: import.id }
        sql = ->(text) { ActiveRecord::Base.sanitize_sql_array([ text, binds ]) }
        Sql.connection.execute(sql.call("insert into import_rejections (import_id, line, reason, ignored) select r.import_id, r.line, #{Sql.connection.quote(label)}, true #{join}"))
        Sql.connection.execute(sql.call(<<~SQL))
          update payment_rows set ok = false, registered = true where import_id = :i and line in (select r.line #{join})
        SQL
      end

      # R61: pagamento não encontrado no canal; data anterior ao pagamento; valor maior que o saldo estornável.
      def reject_reversal_problems(import)
        t = import.tenant_id
        i = import.id
        found = "from payment_rows r join payment_channels ch on ch.tenant_id = ? and ch.code = r.channel_code"
        match = "p.tenant_id = ? and p.channel_id = ch.id and p.identifier = r.payment_identifier"

        Sql.run(<<~SQL, t, i, t)
          insert into import_rejections (import_id, line, reason)
          select r.import_id, r.line, 'pagamento não encontrado no canal' #{found}
          where r.import_id = ? and r.ok and not exists (select 1 from payments p where #{match})
        SQL
        Sql.run(<<~SQL, i, t, t)
          update payment_rows r set ok = false from payment_channels ch
          where r.import_id = ? and r.ok and ch.tenant_id = ? and ch.code = r.channel_code
            and not exists (select 1 from payments p where #{match})
        SQL

        Sql.run(<<~SQL, t, t, i)
          insert into import_rejections (import_id, line, reason)
          select r.import_id, r.line, 'data do estorno anterior ao pagamento' #{found}
          join payments p on #{match} where r.import_id = ? and r.ok and r.paid_on < p.paid_on
        SQL
        Sql.run(<<~SQL, i, t, t)
          update payment_rows r set ok = false from payment_channels ch, payments p
          where r.import_id = ? and r.ok and ch.tenant_id = ? and ch.code = r.channel_code and #{match} and r.paid_on < p.paid_on
        SQL

        # Valor acima do que ainda não foi estornado do pagamento, somando as linhas do próprio arquivo em ordem.
        over = Sql.rows(<<~SQL, t, t, i)
          select x.line, x.reversible - (x.cum - x.amount_cents) as left_cents from (
            select r.line, r.amount_cents, p.amount_cents - p.reversed_cents as reversible,
                   sum(r.amount_cents) over (partition by p.id order by r.paid_on, r.line) as cum
            from payment_rows r join payment_channels ch on ch.tenant_id = ? and ch.code = r.channel_code
            join payments p on p.tenant_id = ? and p.channel_id = ch.id and p.identifier = r.payment_identifier
            where r.import_id = ? and r.ok) x where x.cum > x.reversible
        SQL
        over.each_slice(1000) do |chunk|
          ImportRejection.insert_all(chunk.map { |row| { import_id: i, line: row["line"], reason: "valor maior que o saldo estornável de R$ #{Money.format([ row['left_cents'].to_i, 0 ].max)}" } })
          Sql.run("update payment_rows set ok = false where import_id = ? and line in (?)", i, chunk.map { |row| row["line"] })
        end
      end

      def summarize(import, file, lines, effect)
        id = import.id
        ok = Sql.one("select count(*) as n, coalesce(sum(amount_cents), 0) as amount from payment_rows where import_id = ? and ok", id)
        { lines: lines, valid: ok["n"].to_i, rejected: ImportRejection.where(import_id: id, ignored: false).count,
          ignored: ImportRejection.where(import_id: id, ignored: true).count, blank_lines: file.blank_lines, ignored_columns: file.ignored_columns,
          amount_cents: ok["amount"].to_i, amount_formatted: Money.format(ok["amount"].to_i), effect: effect }
      end

      def number(value) = value.to_s.reverse.scan(/\d{1,3}/).join(".").reverse
  end
end
