module Distributions
  # As distribuições na linha do tempo da ficha (padrões de interface, revisões 23 e 24; `CustomerTimeline`), só para a equipe do credor: do passado até hoje, uma
  # entrada por distribuição que já começou e uma saída quando ela já acabou (encerrada, ou o fim do período já passou). Nada previsto. A mais
  # recente em cima. Com o contrato escolhido no filtro da ficha, só as daquele contrato e as do cliente. Índices: `distributions (tenant_id,
  # customer_id)` e `(tenant_id, contract_id)`.
  module Timeline
    # `at` ordena com os outros eventos da linha do tempo da ficha (`CustomerTimeline`): o início à meia-noite do dia, a saída no momento do
    # encerramento (ou à meia-noite do fim do período); `with_time` diz se a hora vale ser mostrada.
    Event = Data.define(:date, :at, :with_time, :kind, :operation, :detail) do
      def entry? = kind == :entry
    end

    SOURCES = { "manual" => "à mão", "batch" => "em lote", "rule" => "pela regra" }.freeze

    module_function

    def for(customer, contract_ids, today: Date.current)
      distributions = Distribution.where(tenant_id: customer.tenant_id).where(customer_id: customer.id).or(Distribution.where(tenant_id: customer.tenant_id, contract_id: contract_ids))
                                  .where(starts_on: ..today).includes(:operation, :contract).to_a
      events = distributions.flat_map do |distribution|
        target = distribution.contract ? "Contrato #{distribution.contract.label}" : "Cliente"
        entry = Event.new(distribution.starts_on, distribution.starts_on.in_time_zone, false, :entry, distribution.operation,
                          [ target, I18n.t("distributions.exposures.#{distribution.exposure}").downcase, SOURCES[distribution.source] ].compact.join(" · "))
        [ entry, exit_of(distribution, today) ].compact
      end
      # No mesmo dia, a saída veio depois da entrada: em ordem decrescente, fica em cima.
      events.sort_by { |event| [ event.at, event.entry? ? 0 : 1 ] }.reverse
    end

    def exit_of(distribution, today)
      if distribution.ended_at
        Event.new(distribution.ended_at.in_time_zone.to_date, distribution.ended_at, true, :exit, distribution.operation, I18n.t("distributions.end_reasons.#{distribution.end_reason || 'other'}").upcase_first)
      elsif distribution.ends_on && distribution.ends_on < today
        Event.new(distribution.ends_on, distribution.ends_on.in_time_zone.end_of_day, false, :exit, distribution.operation, I18n.t("distributions.end_reasons.period_end").upcase_first)
      end
    end
  end
end
