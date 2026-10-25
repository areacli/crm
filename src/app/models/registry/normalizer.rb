module Registry
  # Normalização para comparar duplicidade (R125) e validação de formato (R111). Cada método devolve um `ParsedContact` ou, quando o
  # formato é inválido, o motivo (texto) — nunca levanta erro, porque na carga o contato inválido é ignorado com aviso.
  module Normalizer
    UFS = %w[AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO].freeze
    STREET_ABBREVIATIONS = { "R" => "RUA", "AV" => "AVENIDA", "TV" => "TRAVESSA", "AL" => "ALAMEDA", "PC" => "PRACA", "PCA" => "PRACA",
                             "EST" => "ESTRADA", "ROD" => "RODOVIA" }.freeze
    EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
    MAX_LENGTH = { street: 200, number: 20, complement: 100, district: 100, city: 100 }.freeze
    LABELS = { street: "logradouro", city: "cidade", state: "UF", zip: "CEP" }.freeze
    FIELD_NAMES = LABELS.merge(number: "número", complement: "complemento", district: "bairro").freeze

    module_function

    # Só os dígitos; tira o código do país 55 e o 0 (com o código de operadora, se houver) da frente. O resultado é DDD + número (10 ou 11
    # dígitos). Sem DDD (8 ou 9 dígitos) guarda como veio, com o aviso. Não acrescenta o 9 dos celulares antigos (DC4).
    def phone(raw)
      digits = raw.to_s.delete("^0-9")
      trunk = digits.start_with?("0")
      digits = digits.sub(/\A0+/, "")
      digits = digits[2..] if digits.length.between?(12, 13) && (digits.start_with?("55") || trunk)
      return "menos de 8 dígitos" if digits.length < 8
      return "dígitos demais" if digits.length > 11
      return ParsedContact.simple("phone", digits, raw.to_s.strip, "telefone sem DDD") if digits.length <= 9
      return "DDD inválido" if digits[0, 2].to_i < 11

      ParsedContact.simple("phone", digits, raw.to_s.strip)
    end

    # Sem espaços nas pontas, em minúsculas.
    def email(raw)
      value = raw.to_s.strip
      return "formato inválido" unless value.match?(EMAIL_FORMAT)

      ParsedContact.simple("email", value.downcase, value)
    end

    # `fields`: street, number, complement, district, city, state, zip (texto como veio). Tudo vazio não é endereço (nil); campo obrigatório
    # faltando, CEP ou UF inválidos tornam o endereço inválido. Escrito sem alocações extras: na V4 de cadastros a carga de 200 mil linhas
    # normaliza 200 mil endereços.
    def address(fields)
      street = fields[:street].to_s.strip
      number = fields[:number].to_s.strip
      complement = fields[:complement].to_s.strip
      district = fields[:district].to_s.strip
      city = fields[:city].to_s.strip
      state = fields[:state].to_s.strip
      zip_raw = fields[:zip].to_s.strip
      return if street.empty? && number.empty? && complement.empty? && district.empty? && city.empty? && state.empty? && zip_raw.empty?

      missing = []
      missing << "logradouro" if street.empty?
      missing << "cidade" if city.empty?
      missing << "UF" if state.empty?
      missing << "CEP" if zip_raw.empty?
      return "incompleto (falta #{missing.size > 1 ? "#{missing[0..-2].join(', ')} e #{missing.last}" : missing.first})" if missing.any?
      return "CEP inválido" unless zip_raw.match?(/\A\d{5}-?\d{3}\z/)

      state = state.upcase
      return "UF inválida" unless UFS.include?(state)

      { street: street, number: number, complement: complement, district: district, city: city }.each do |field, value|
        return "#{FIELD_NAMES.fetch(field)} acima de #{MAX_LENGTH.fetch(field)} caracteres" if value.length > MAX_LENGTH.fetch(field)
      end

      zip = zip_raw.delete("-")
      number = number.delete("^0-9").presence || "s/n"
      value = +"#{street}, #{number}"
      value << ", #{complement}" unless complement.empty?
      value << ", #{district}" unless district.empty?
      value << ", #{city}/#{state}, CEP #{zip[0, 5]}-#{zip[5, 3]}"
      ParsedContact.new("address", "#{zip}|#{number}|#{street_key(street)}", value, street, number, complement.presence, district.presence, city, state, zip, nil)
    end

    # Logradouro sem acentos, pontuação e espaços repetidos, em maiúsculas, com a abreviação do começo por extenso.
    def street_key(street)
      words = FoldedText.fold(street).gsub(/[^a-z0-9]+/, " ").strip.upcase.split
      words[0] = STREET_ABBREVIATIONS.fetch(words[0], words[0]) if words.any?
      words.join(" ")
    end

    # A chave de um valor digitado livremente (o contato do credor, o contato usado no acionamento), pelo tipo.
    def key_for(kind, raw)
      result = kind.to_s == "phone" ? phone(raw) : (kind.to_s == "email" ? email(raw) : nil)
      result.is_a?(ParsedContact) ? result.key : nil
    end
  end
end
