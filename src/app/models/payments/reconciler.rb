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

    # Desde a revisão 5: os dias vêm do manifesto de cada fornecedor (`reconcile_after_days`, R284r; sem declaração, os da configuração), e entram também
    # os cancelados só aqui que o fornecedor ainda aceita (R284o), até ele os mostrar vencidos ou cancelados. Os ativos usam o índice de sempre; os
    # cancelados só aqui são poucos (só de fornecedor sem cancelamento) e vão pelo credor.
    def due(now = Time.current)
      default_days = Rails.configuration.x.payments.reconcile_after_days
      special = Payments::Providers.names.filter_map do |name|
        days = Payments::Providers.manifest(name).capabilities[:reconcile_after_days]
        [ name, days ] if days && days != default_days
      end
      groups = [ [ nil, default_days ], *special.group_by(&:last).map { |days, pairs| [ pairs.map(&:first), days ] } ]
      sql = groups.map do |providers, days|
        limit = now - days.days
        filter = providers ? sanitize("provider in (?)", providers) : (special.any? ? sanitize("provider not in (?)", special.map(&:first)) : "true")
        "(#{filter} and #{sanitize('(reconciled_at <= ? or (reconciled_at is null and coalesce(issued_at, created_at) <= ?))', limit, limit)})"
      end.join(" or ")
      base = PaymentInstrument.where(tenant_id: @tenant.id).where.not(external_id: nil).where(sql)
      # Duas consultas unidas, para cada uma usar o seu caminho: os ativos pelo índice parcial de sempre; os cancelados só aqui, poucos, pelo credor.
      active = base.where(state: "active")
      canceled = base.where(state: "canceled").where("response_summary ? 'canceled_locally_at' and not response_summary ? 'canceled_locally_closed_at'")
      PaymentInstrument.from("(#{active.to_sql} union all #{canceled.to_sql}) payment_instruments").order(:id)
    end

    private
      def sanitize(*arguments) = ActiveRecord::Base.sanitize_sql_array(arguments)
  end
end
