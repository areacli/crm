module Payments
  # Conciliação diária de um credor (12, parte D, R283): reprocessa os avisos que falharam e confere no fornecedor os instrumentos ATIVOS que não foram
  # conferidos há `reconcile_after_days` dias (boleto e Pix vencidos ou não, cartão aprovado ainda sem confirmação), para pegar o aviso que nunca chegou.
  # Um job por instrumento, espaçados pelo limite de consultas por minuto (como a emissão em lote); a execução vira um `TaskRun` do credor (O8). Sem
  # polling de tela: a mudança chega ao navegador pelos mesmos eventos do pagamento. Consulta: `index_payment_instruments_to_reconcile` (só os ativos).
  class Reconciler
    NAME = "payment_reconciliation"

    def initialize(tenant) = @tenant = tenant

    def call(now: Time.current, per_minute: nil)
      run = TaskRun.create!(tenant: @tenant, name: NAME, started_at: now)
      reprocessed = EventReprocessor.new(@tenant).call(now: now)
      interval = 60.0 / [ per_minute || Rails.configuration.x.payments.reconcile_per_minute, 1 ].max
      count = 0
      due(now).find_each.with_index do |instrument, index|
        ReconcileInstrumentJob.set(wait: (index * interval).seconds).perform_later(instrument, run)
        count += 1
      end
      run.update!(status: :succeeded, finished_at: Time.current, processed: count, note: I18n.t("payments.reconcile.note", reprocessed: reprocessed, count: count))
      run
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { tenant_id: @tenant.id })
      run&.update!(status: :failed, finished_at: Time.current, error_kind: error.class.name.demodulize)
      run
    end

    def due(now = Time.current)
      limit = now - Rails.configuration.x.payments.reconcile_after_days.days
      PaymentInstrument.where(tenant_id: @tenant.id, state: "active").where.not(external_id: nil)
                       .where("reconciled_at <= ? or (reconciled_at is null and coalesce(issued_at, created_at) <= ?)", limit, limit).order(:id)
    end
  end
end
