module Payments
  # Aplica (ou só simula) os estornos de uma importação (R60 a R63): o valor estornado sai primeiro do crédito que o pagamento gerou e,
  # depois, do título, que volta à cobrança sozinho se estava pago (R62, R62a).
  class ReversalProcessor
    CHUNK = 2000

    Sql = Portfolio::Sql

    # Chaves do resumo: reopened, credit_reduced, pending_reduced, from_bill_cents, from_credit_cents, reversed_cents.
    def run(import, commit:)
      tenant_id = import.tenant_id
      setting = TenantSetting.find_by!(tenant_id: tenant_id)
      summary = Hash.new(0)

      Sql.connection.execute("drop table if exists reversal_stream")
      Sql.run(<<~SQL, tenant_id, tenant_id, import.id)
        create temporary table reversal_stream on commit drop as
        select row_number() over (order by r.paid_on, r.line) as n, r.line, r.identifier, r.paid_on as reversed_on, r.amount_cents, r.reason,
               p.id as payment_id, p.channel_id, p.status as payment_status, p.amount_cents as payment_amount, p.applied_cents, p.credit_cents,
               p.reversed_cents, p.credit_reversed_cents, p.bill_id, b.contract_id, b.amount_cents as bill_amount, b.paid_cents, b.paid_on as bill_paid_on, b.status as bill_status, b.withdrawn_at
        from payment_rows r
        join payment_channels ch on ch.tenant_id = ? and ch.code = r.channel_code
        join payments p on p.tenant_id = ? and p.channel_id = ch.id and p.identifier = r.payment_identifier
        left join bills b on b.id = p.bill_id
        where r.import_id = ? and r.ok
      SQL
      Sql.connection.execute("create unique index on reversal_stream (n)")
      Sql.connection.execute("analyze reversal_stream")
      total = Sql.one("select count(*) as n from reversal_stream")["n"].to_i

      payments = {}
      bills = {}
      (1..total).step(CHUNK) do |from|
        rows = Sql.rows("select * from reversal_stream where n between ? and ? order by n", from, from + CHUNK - 1)
        reversals = []
        credits = []
        changes = []
        touched_payments = {}
        touched_bills = {}

        rows.each do |row|
          payment_id = row["payment_id"].to_i
          payment = payments[payment_id] ||= { reversed: row["reversed_cents"].to_i, credit_reversed: row["credit_reversed_cents"].to_i, status: row["payment_status"] }
          amount = row["amount_cents"].to_i
          summary[:reversed_cents] += amount
          from_credit = 0
          from_bill = 0

          if row["bill_id"].nil?
            # Pagamento pendente estornado deixa de ser pendente pelo valor estornado (R62).
            summary[:pending_reduced] += 1
          else
            from_credit = [ amount, row["credit_cents"].to_i - payment[:credit_reversed] ].min
            from_bill = amount - from_credit
            payment[:credit_reversed] += from_credit
            if from_credit.positive?
              summary[:credit_reduced] += 1
              summary[:from_credit_cents] += from_credit
              credits << { tenant_id: tenant_id, contract_id: row["contract_id"].to_i, payment_id: payment_id, user_id: import.user_id, kind: "reversal",
                           amount_cents: -from_credit, reason: "reversed", occurred_at: Time.current }
            end
            if from_bill.positive?
              bill_id = row["bill_id"].to_i
              bill = bills[bill_id] ||= { paid: row["paid_cents"].to_i, status: row["bill_status"], paid_on: row["bill_paid_on"] }
              bill[:paid] -= from_bill
              summary[:from_bill_cents] += from_bill
              # R92: o estorno consome primeiro o excedente (valor reduzido abaixo do alocado); o título só volta à cobrança se o saldo reabre.
              if bill[:status] == "paid" && bill[:paid] < row["bill_amount"].to_i
                # R62a: o título que o credor tinha retirado segue a política; os demais voltam à cobrança.
                bill[:status] = row["withdrawn_at"].present? && setting.withdrawn_reversal_policy_withdrawn? ? "withdrawn" : "active"
                bill[:paid_on] = nil
                summary[:reopened] += 1
              end
              touched_bills[bill_id] = true
              changes << { subject_type: "bill", subject_id: bill_id, event: "payment_reversed", after: bill[:paid].to_s }
            end
          end

          payment[:reversed] += amount
          payment[:status] = "cancelled" if row["bill_id"].nil? && payment[:reversed] >= row["payment_amount"].to_i
          touched_payments[payment_id] = true
          reversals << { tenant_id: tenant_id, channel_id: row["channel_id"].to_i, payment_id: payment_id, import_id: import.id, identifier: row["identifier"],
                         reversed_on: row["reversed_on"], amount_cents: amount, from_credit_cents: from_credit, from_bill_cents: from_bill, reason: row["reason"] }
        end

        write(import, reversals, credits, changes, payments.slice(*touched_payments.keys), bills.slice(*touched_bills.keys)) if commit
      end
      summary.to_h.symbolize_keys
    end

    private
      REVERSAL_COLUMNS = %w[tenant_id channel_id payment_id import_id identifier reversed_on amount_cents from_credit_cents from_bill_cents reason created_at updated_at].freeze

      # Grava pelo COPY (ver Payments::Processor#write).
      def write(import, reversals, credits, changes, payments, bills)
        now = Time.current
        Sql.copy_in("payment_reversals", REVERSAL_COLUMNS, reversals.map { |row| REVERSAL_COLUMNS.map { |column| row.fetch(column.to_sym) { now } } })
        Sql.copy_in("credits", %w[tenant_id contract_id payment_id user_id kind amount_cents reason occurred_at],
                    credits.map { |row| [ row[:tenant_id], row[:contract_id], row[:payment_id], row[:user_id], row[:kind], row[:amount_cents], row[:reason], row[:occurred_at] ] })
        Sql.copy_in("changes", %w[tenant_id user_id import_id subject_type subject_id event after occurred_at],
                    changes.map { |row| [ import.tenant_id, import.user_id, import.id, row[:subject_type], row[:subject_id], row[:event], row[:after], now ] })

        payments.each_slice(CHUNK) do |slice|
          values = slice.map { |id, p| "(#{id.to_i}::bigint, #{p[:reversed].to_i}::bigint, #{p[:credit_reversed].to_i}::bigint, #{Sql.connection.quote(p[:status])}::varchar)" }.join(",")
          Sql.run("update payments set reversed_cents = v.reversed, credit_reversed_cents = v.credit_reversed, status = v.status, updated_at = now() " \
                  "from (values #{values}) as v(id, reversed, credit_reversed, status) where payments.id = v.id")
        end
        bills.each_slice(CHUNK) do |slice|
          values = slice.map { |id, b| "(#{id.to_i}::bigint, #{b[:paid].to_i}::bigint, #{Sql.connection.quote(b[:status])}::varchar, #{Sql.connection.quote(b[:paid_on])}::date)" }.join(",")
          Sql.run("update bills set paid_cents = v.paid, status = v.status, paid_on = v.paid_on, updated_at = now() " \
                  "from (values #{values}) as v(id, paid, status, paid_on) where bills.id = v.id")
        end
      end
  end
end
