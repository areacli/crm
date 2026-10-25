module Payments
  # Valida e normaliza uma linha da planilha de pagamentos (R49, R52a). Devolve [linha normalizada, nil] ou [nil, motivo da recusa].
  class PaymentRowValidator
    ParsedRow = Data.define(:line, :channel_code, :identifier, :document, :bill_number, :paid_on, :amount_cents, :payment_method)

    FIELD_NAMES = { "canal" => "canal", "identificador" => "identificador", "documento" => "documento", "data_pagamento" => "data de pagamento",
                    "valor" => "valor", "meio" => "meio" }.freeze

    def validate(csv_row)
      values = csv_row.values
      return [ nil, "linha com mais colunas que o cabeçalho" ] if csv_row.extra
      return [ nil, "linha incompleta" ] if csv_row.short

      FIELD_NAMES.each { |field, label| return [ nil, "#{label} obrigatório" ] if values[field].blank? }
      # R52a: todo pagamento identifica um título; sem ele a linha é recusada.
      return [ nil, "título não informado" ] if values["titulo"].blank?
      return [ nil, "identificador acima de 200 caracteres" ] if values["identificador"].length > 200
      return [ nil, "canal ou título acima de 100 caracteres" ] if values["canal"].length > 100 || values["titulo"].length > 100

      problem = Document.problem(values["documento"])
      return [ nil, problem ] if problem

      date = BrDate.parse(values["data_pagamento"])
      return [ nil, "data inválida" ] unless date
      return [ nil, "data de pagamento futura" ] if date > Date.current

      cents, money_problem = Money.parse_cents(values["valor"])
      return [ nil, money_problem ] unless cents

      method = Payment.method_from_sheet(values["meio"])
      return [ nil, "meio de pagamento fora da lista" ] unless method

      [ ParsedRow.new(line: csv_row.line, channel_code: values["canal"], identifier: values["identificador"], document: Document.normalize(values["documento"]),
                      bill_number: values["titulo"], paid_on: date, amount_cents: cents, payment_method: method), nil ]
    end
  end
end
