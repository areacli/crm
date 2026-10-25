module Charges
  # As regras efetivas de um credor: a de cada segmento com o que ele herda dos parâmetros do credor (R160, R207a), as políticas e as tabelas.
  # Serve ao recálculo, à ficha, à conferência do impacto (que passa a proposta no lugar do que está gravado) e ao pagamento.
  module RuleSet
    PARAMS = %i[charge_fine_pct charge_interest_pct charge_index charge_days_convention charge_fine_base].freeze
    SEGMENT_FIELDS = %i[name fine_pct interest_kind interest_pct interest_form index_code fees_pct fees_in_contract days_convention fine_base].freeze

    module_function

    def params_of(setting) = PARAMS.index_with { |name| setting[name] }

    def segment_values(segment) = SEGMENT_FIELDS.index_with { |name| segment[name] }

    # { id do segmento => Rule } do que está gravado.
    def rules(tenant)
      params = params_of(tenant.setting)
      Segment.where(tenant_id: tenant.id).to_h { |segment| [ segment.id, Rule.build(segment_values(segment), params) ] }
    end

    def demais_id(tenant) = Segment.where(tenant_id: tenant.id, catch_all: true).pick(:id)

    # { série => { mês => percentual } }: só meses fechados do Banco Central, com a correção do credor por cima (R145); o mês incluído à mão
    # também vale. A taxa legal é sempre fechada (R162, gravada com `partial: false`).
    def rates(tenant)
      rates = Hash.new { |hash, key| hash[key] = {} }
      IndexRate.where(partial: false).pluck(:series, :month, :value).each { |series, month, value| rates[series][month] = value.to_f }
      IndexAdjustment.where(tenant_id: tenant.id).pluck(:series, :month, :value).each { |series, month, value| rates[series][month] = value.to_f }
      rates
    end

    def tables(tenant, today, policies: Policies.of(tenant.setting), rates: self.rates(tenant)) = Tables.new(rates, today, policies)
  end
end
