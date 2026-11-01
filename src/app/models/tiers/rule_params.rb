module Tiers
  # Lê o formulário das regras de um item do enquadramento financeiro (13, R294): encargos (09, R160) e prazo da promessa (10, R189). Texto que não
  # é número vira erro do campo, com o texto digitado de volta na tela.
  module RuleParams
    PERCENT = /\A\d{1,3}(?:[.,]\d{1,4})?\z/
    CHARGE_FIELDS = (Tier::CHARGE_FIELDS + %i[promise_max_days]).freeze

    # Percentual digitado (vírgula ou ponto, até 4 casas): BigDecimal, nil se vazio, :invalid se não é número.
    def self.percent(text)
      text = text.to_s.strip
      return nil if text.empty?

      text.match?(PERCENT) ? BigDecimal(text.tr(",", ".")) : :invalid
    end

    module_function

    # Regra de encargos (09, R160): vazio nos campos herdados fica nil (herda do credor); honorários vazio é zero. Forma, taxa legal e honorários
    # são só do item. Devolve [atributos, { campo => chave do erro }].
    def parse(raw)
      attributes = {}
      invalid = {}
      { fine_pct: nil, interest_pct: nil, fees_pct: 0 }.each do |column, empty|
        value = RuleParams.percent(raw[column])
        value == :invalid ? invalid[column] = :percent_invalid : attributes[column] = value.nil? ? empty : value
      end
      attributes[:interest_kind] = raw[:interest_kind].presence_in(Tier::INTEREST_KINDS) || "none"
      attributes[:interest_form] = raw[:interest_form].presence_in(Tier::INTEREST_FORMS) || "simple"
      attributes[:index_code] = raw[:index_code].presence_in(Tier::INDEX_CODES)
      attributes[:fees_in_contract] = raw[:fees_in_contract].to_s == "1"
      attributes[:days_convention] = raw[:days_convention].presence_in(Tier::DAYS_CONVENTIONS)
      attributes[:fine_base] = raw[:fine_base].presence_in(Tier::FINE_BASES)
      days = raw[:promise_max_days].to_s.strip
      days.match?(/\A\d{1,3}\z/) ? attributes[:promise_max_days] = days.to_i : invalid[:promise_max_days] = :number_invalid
      [ attributes, invalid ]
    end
  end
end
