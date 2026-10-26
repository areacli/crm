module Promises
  # Tarefa diária das promessas de um credor (10, R193, R197; O8): quebra a promessa aberta cujo prazo passou sem cumprir, com o percentual pago, e termina
  # como não aprovada a pendente cujo prazo passou. Os títulos ficam livres (sujeitos à carência) e voltam à regra normal. O prazo é o congelado na promessa
  # (data prometida mais a tolerância de dias, DP12). Processamento em lote (decisão 0021): a consulta é de conjunto, a gravação é Active Record em fatias de 1.000
  # promessas (uma transação cada), com a auditoria única (`Change.record_many!`) e um aviso só ao fim.
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
      # O aviso das telas sai uma vez, no fim: o `after_commit` de cada promessa só dispara depois do commit, então o modo silencioso envolve a transação.
      Broadcast.quiet do
        ApplicationRecord.transaction do
          changed += move("open", "broken", today)
          changed += move("pending", "not_approved", today)
        end
      end
      Broadcast.changed(@tenant, customers_of(changed.first(200))) if changed.any?
      changed.size
    end

    private
      def move(from, to, today)
        due = PaymentPromise.where(tenant_id: @tenant.id, state: from).where("promised_on + coalesce((policies->>'tolerance_days')::int, 3) < ?::date", today)
        ids = []
        due.in_batches(of: 1000) do |batch|
          promises = batch.preload(:customer, :contract, :contact_attempt).to_a
          Broadcast.quiet do
            ApplicationRecord.transaction do
              promises.each { |promise| promise.update!(state: to, closed_at: Time.current, paid_percent: promise.paid_percent_value) }
              PaymentPromiseBill.where(promise_id: promises.map(&:id), held: true).update_all(held: false)
              Change.record_many!(promises.map { |promise| [ promise, "state_changed", { field: "state", before: from, after: to } ] }, tenant_id: @tenant.id)
            end
          end
          ids.concat(promises.map(&:id))
        end
        ids
      end

      def customers_of(ids)
        return [] if ids.empty?

        Sql.rows("select distinct cc.customer_id from payment_promises p join contract_customers cc on cc.contract_id = p.contract_id where p.id in (?)", ids).map { |row| row["customer_id"].to_i }
      end
  end
end
