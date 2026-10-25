module Segments
  # Lê o formulário do segmento: números inteiros, saldo em reais (centavos), tipo, "já quebrou acordo" e a lista de produtos (separados por
  # vírgula ou linha). Texto que não é número vira erro do campo, com o texto digitado de volta na tela.
  module Params
    MONEY = /\A(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?\z/
    PERCENT = /\A\d{1,3}(?:[.,]\d{1,4})?\z/
    FIELDS = (Segment::RANGE_COLUMNS + %i[name person_type broke_agreement products] + Segment::CHARGE_FIELDS).freeze

    # Percentual digitado (vírgula ou ponto, até 4 casas): BigDecimal, nil se vazio, :invalid se não é número.
    def self.percent(text)
      text = text.to_s.strip
      return nil if text.empty?

      text.match?(PERCENT) ? BigDecimal(text.tr(",", ".")) : :invalid
    end

    module_function

    # Regra de encargos (09, R160): vazio nos campos herdados fica nil (herda do credor); honorários vazio é zero. Forma, taxa legal e honorários
    # são só do segmento.
    def parse_charges(raw, attributes, invalid)
      { fine_pct: nil, interest_pct: nil, fees_pct: 0 }.each do |column, empty|
        value = Params.percent(raw[column])
        value == :invalid ? invalid[column] = :percent_invalid : attributes[column] = value.nil? ? empty : value
      end
      attributes[:interest_kind] = raw[:interest_kind].presence_in(Segment::INTEREST_KINDS) || "none"
      attributes[:interest_form] = raw[:interest_form].presence_in(Segment::INTEREST_FORMS) || "simple"
      attributes[:index_code] = raw[:index_code].presence_in(Segment::INDEX_CODES)
      attributes[:fees_in_contract] = raw[:fees_in_contract].to_s == "1"
      attributes[:days_convention] = raw[:days_convention].presence_in(Segment::DAYS_CONVENTIONS)
      attributes[:fine_base] = raw[:fine_base].presence_in(Segment::FINE_BASES)
    end

    # Devolve [atributos, { campo => chave do erro }].
    def parse(raw)
      attributes = { name: raw[:name].to_s }
      invalid = {}
      Segment::RANGE_COLUMNS.each do |column|
        text = raw[column].to_s.strip
        if text.empty?
          attributes[column] = nil
        elsif column.to_s.end_with?("balance_cents")
          match = text.match(MONEY)
          match ? attributes[column] = match[1].delete(".").to_i * 100 + match[2].to_s.ljust(2, "0").to_i : invalid[column] = :money_invalid
        elsif text.match?(/\A-?\d{1,9}\z/)
          attributes[column] = text.to_i
        else
          invalid[column] = :number_invalid
        end
      end
      attributes[:person_type] = raw[:person_type].presence_in(Segment::PERSON_TYPES)
      attributes[:broke_agreement] = raw[:broke_agreement].presence_in(%w[yes no])
      attributes[:products] = raw[:products].to_s.split(/[,;\n]/)
      parse_charges(raw, attributes, invalid)
      [ attributes, invalid ]
    end
  end
end
