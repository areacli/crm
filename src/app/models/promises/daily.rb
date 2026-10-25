module Promises
  # Tarefa diária das promessas de um credor (10, R193, R197; O8): quebra a promessa aberta cujo prazo passou sem cumprir, com o percentual pago, e termina
  # como não aprovada a pendente cujo prazo passou. Os títulos ficam livres (sujeitos à carência) e voltam à regra normal. O prazo é o congelado na promessa
  # (data prometida mais a tolerância de dias, DP12). Em SQL de conjunto: 50 mil promessas abertas por credor cabem nos 2 minutos.
  class Daily
    NAME = "promises_daily"
    Sql = Portfolio::Sql

    def initialize(tenant) = @tenant = tenant

    def call(today: Date.current)
      run = TaskRun.create!(tenant: @tenant, name: NAME, started_at: Time.current)
      count = apply(today: today)
      run.update!(status: :succeeded, finished_at: Time.current, processed: count)
      run
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { tenant_id: @tenant.id })
      run&.update!(status: :failed, finished_at: Time.current, error_kind: error.class.name.demodulize)
      run
    end

    # Devolve quantas promessas mudaram de estado.
    def apply(today: Date.current)
      changed = []
      ApplicationRecord.transaction do
        changed += move("open", "broken", today)
        changed += move("pending", "not_approved", today)
      end
      Broadcast.changed(@tenant, customers_of(changed.first(200))) if changed.any?
      changed.size
    end

    private
      def move(from, to, today)
        rows = Sql.rows(<<~SQL, to, @tenant.id, from, today)
          update payment_promises set state = ?, closed_at = now(), updated_at = now(), paid_percent = coalesce(round(paid_cents * 100.0 / nullif(total_cents, 0)), 0)
          where tenant_id = ? and state = ? and promised_on + coalesce((policies->>'tolerance_days')::int, 3) < ?::date
          returning id
        SQL
        ids = rows.map { |row| row["id"].to_i }
        ids.each_slice(2000) { |slice| Sql.run("update payment_promise_bills set held = false where promise_id in (?) and held", slice) }
        Sql.copy_in("changes", %w[tenant_id subject_type subject_id event field before after occurred_at], ids.map { |id| [ @tenant.id, "payment_promise", id, "state_changed", "state", from, to, Time.current ] })
        ids
      end

      def customers_of(ids)
        return [] if ids.empty?

        Sql.rows("select distinct cc.customer_id from payment_promises p join contract_customers cc on cc.contract_id = p.contract_id where p.id in (?)", ids).map { |row| row["customer_id"].to_i }
      end
  end
end
