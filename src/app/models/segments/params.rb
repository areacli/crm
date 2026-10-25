module Segments
  # Lê o formulário do segmento: números inteiros, saldo em reais (centavos), tipo, "já quebrou acordo" e a lista de produtos (separados por
  # vírgula ou linha). Texto que não é número vira erro do campo, com o texto digitado de volta na tela.
  module Params
    MONEY = /\A(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?\z/
    FIELDS = (Segment::RANGE_COLUMNS + %i[name person_type broke_agreement products]).freeze

    module_function

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
      [ attributes, invalid ]
    end
  end
end
