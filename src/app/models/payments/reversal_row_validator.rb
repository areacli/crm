module Payments
  # Valida e normaliza uma linha da planilha de estornos (R60, R61). Devolve [linha normalizada, nil] ou [nil, motivo da recusa].
  class ReversalRowValidator
    ParsedRow = Data.define(:line, :channel_code, :payment_identifier, :identifier, :paid_on, :amount_cents, :reason)

    FIELD_NAMES = { "canal" => "canal", "identificador_pagamento" => "identificador do pagamento", "identificador_estorno" => "identificador do estorno",
                    "data_estorno" => "data do estorno", "valor" => "valor" }.freeze

    def validate(csv_row)
      values = csv_row.values
      return [ nil, "linha com mais colunas que o cabeçalho" ] if csv_row.extra
      return [ nil, "linha incompleta" ] if csv_row.short

      FIELD_NAMES.each { |field, label| return [ nil, "#{label} obrigatório" ] if values[field].blank? }
      return [ nil, "identificador ou canal acima do limite" ] if values["identificador_estorno"].length > 200 || values["identificador_pagamento"].length > 200 ||
                                                                  values["canal"].length > 100
      return [ nil, "motivo acima de 300 caracteres" ] if values["motivo"].to_s.length > 300

      date = BrDate.parse(values["data_estorno"])
      return [ nil, "data inválida" ] unless date
      return [ nil, "data de estorno futura" ] if date > Date.current

      cents, money_problem = Money.parse_cents(values["valor"])
      return [ nil, money_problem ] unless cents

      [ ParsedRow.new(line: csv_row.line, channel_code: values["canal"], payment_identifier: values["identificador_pagamento"],
                      identifier: values["identificador_estorno"], paid_on: date, amount_cents: cents, reason: values["motivo"].presence), nil ]
    end
  end
end
