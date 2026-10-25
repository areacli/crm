module Registry
  # Contatos de uma linha da carga (R109, R110, R111): telefone e telefone2 a telefone5, email e email2 a email5 e o endereço em colunas
  # separadas. Contato com formato inválido é ignorado com aviso (a linha entra); dois iguais na mesma linha viram um só.
  module LoadContacts
    PHONES = %w[telefone telefone2 telefone3 telefone4 telefone5].freeze
    EMAILS = %w[email email2 email3 email4 email5].freeze
    ADDRESS = { street: "logradouro", number: "numero", complement: "complemento", district: "bairro", city: "cidade", state: "uf", zip: "cep" }.freeze
    COLUMNS = (PHONES + EMAILS + ADDRESS.values).freeze

    module_function

    # @return [Array(Array<ParsedContact>, Array<String>)] os contatos e os avisos da linha
    def parse(values)
      contacts = []
      warnings = []
      { "phone" => PHONES, "email" => EMAILS }.each do |kind, columns|
        columns.each do |column|
          raw = values[column].to_s.strip
          next if raw.empty?

          result = Normalizer.public_send(kind, raw)
          if result.is_a?(String)
            warnings << "#{column} ignorado (#{result})"
          elsif contacts.none? { |other| other.kind == kind && other.key == result.key }
            contacts << result
            warnings << "#{column} sem DDD (guardado como veio)" if result.warning
          end
        end
      end
      address = Normalizer.address(ADDRESS.transform_values { |column| values[column] })
      if address.is_a?(String)
        warnings << "endereço ignorado (#{address})"
      elsif address
        contacts << address
      end
      [ contacts, warnings ]
    end
  end
end
