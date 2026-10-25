# Documento do cliente: CPF (11 dígitos) ou CNPJ (14 caracteres, numérico ou alfanumérico). O documento é identificado sem
# máscara (R1) e precisa ter dígitos verificadores válidos (R2).
module Document
  module_function

  # Remove a máscara e põe em maiúsculas: "529.982.247-25" vira "52998224725".
  def normalize(raw) = raw.to_s.gsub(/[^0-9A-Za-z]/, "").upcase

  # Motivo da recusa ("CPF inválido", "CNPJ inválido", "documento inválido…") ou nil quando válido.
  def problem(raw)
    document = normalize(raw)
    case document.length
    when 11 then valid_cpf?(document) ? nil : "CPF inválido"
    when 14 then valid_cnpj?(document) ? nil : "CNPJ inválido"
    else "documento inválido: deve ter 11 dígitos (CPF) ou 14 caracteres (CNPJ)"
    end
  end

  # CPF/CNPJ mascarado para a lista; o documento completo só aparece na ficha.
  def mask(document)
    return "#{document[0, 3]}.***.***-#{document[9, 2]}" if document.length == 11

    "#{document[0, 2]}.***.***/****-#{document[12, 2]}"
  end

  # Documento completo com pontuação, para a ficha do cliente.
  def format(document)
    return "#{document[0, 3]}.#{document[3, 3]}.#{document[6, 3]}-#{document[9, 2]}" if document.length == 11

    "#{document[0, 2]}.#{document[2, 3]}.#{document[5, 3]}/#{document[8, 4]}-#{document[12, 2]}"
  end

  def valid_cpf?(cpf)
    return false unless cpf.match?(/\A\d{11}\z/) && !cpf.match?(/\A(\d)\1{10}\z/)

    [ 9, 10 ].all? do |length|
      sum = (0...length).sum { |i| cpf[i].to_i * (length + 1 - i) }
      (sum * 10) % 11 % 10 == cpf[length].to_i
    end
  end

  # CNPJ numérico ou alfanumérico (Receita Federal, desde julho de 2026): cada caractere vale seu código ASCII menos 48; pesos de 2 a 9
  # da direita para a esquerda; módulo 11. Os dois últimos caracteres são sempre dígitos.
  def valid_cnpj?(cnpj)
    return false unless cnpj.match?(/\A[0-9A-Z]{12}[0-9]{2}\z/) && !cnpj.match?(/\A(.)\1{13}\z/)

    [ 12, 13 ].all? do |position|
      weight = 1
      sum = (position - 1).downto(0).sum do |i|
        weight = weight == 9 ? 2 : weight + 1
        (cnpj[i].ord - 48) * weight
      end
      rest = sum % 11
      (rest < 2 ? 0 : 11 - rest) == cnpj[position].to_i
    end
  end
end
