# Valores em reais no formato brasileiro, guardados em centavos inteiros (R5, grande regra 2).
module Money
  module_function

  # Devolve [centavos, nil] ou [nil, motivo da recusa]: "1.234,56", "1234,56", "1234" ou "0,5", com no máximo duas casas.
  def parse_cents(raw)
    value = raw.to_s.strip
    return [ nil, "valor obrigatório" ] if value.empty?

    match = value.match(/\A(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?\z/)
    return [ nil, value.match?(/,\d{3,}\z/) ? "valor com mais de duas casas decimais" : "valor inválido" ] unless match

    total = match[1].delete(".").to_i * 100 + match[2].to_s.ljust(2, "0").to_i
    total.positive? ? [ total, nil ] : [ nil, "valor deve ser maior que zero" ]
  end

  # 123456 -> "1.234,56"
  def format(cents)
    reais, centavos = cents.to_i.abs.divmod(100)
    "#{"-" if cents.to_i.negative?}#{reais.to_s.reverse.scan(/\d{1,3}/).join(".").reverse},#{centavos.to_s.rjust(2, "0")}"
  end
end
