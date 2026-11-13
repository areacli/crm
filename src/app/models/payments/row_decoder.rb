module Payments
  # Converte um pagamento nos tipos do registro canônico (decisão 0031). `decode` lê o texto de um registro de arquivo; `from_event`, um pagamento que já chega
  # com data e centavos (webhook e instrumento pago). Não recusa: o que não pôde ser convertido fica em `format_problems`, e o validador decide.
  class RowDecoder
    Record = Data.define(:position, :extra, :short, :raw, :document, :paid_on, :amount_cents, :payment_method, :final_state, :format_problems)

    # Estado final do arquivo (PG-3, R226): "quitado" dá o título por pago; "parcial" é só informativo; vazio, sem estado.
    FINAL_STATES = { "quitado" => "settled", "parcial" => "partial" }.freeze

    def decode(raw)
      values = raw.values
      problems = {}
      paid_on = BrDate.parse(values["data_pagamento"])
      problems[:paid_on] = "data inválida" unless paid_on
      cents, money_problem = Money.parse_cents(values["valor"])
      problems[:amount] = money_problem if money_problem
      build(position: raw.position, extra: raw.extra, short: raw.short, values: values, paid_on: paid_on, cents: cents, problems: problems)
    end

    # `values` traz os demais campos como chegaram; `paid_on` e `amount_cents` já vêm nos tipos certos.
    def from_event(position:, values:, paid_on:, amount_cents:)
      build(position: position, extra: false, short: false, values: values.merge("data_pagamento" => paid_on.iso8601, "valor" => amount_cents.to_s), paid_on: paid_on, cents: amount_cents, problems: {})
    end

    private
      def build(position:, extra:, short:, values:, paid_on:, cents:, problems:)
        method = Payment.method_from_sheet(values["meio"])
        problems[:payment_method] = "meio de pagamento fora da lista" unless method
        final_state = values["estado_final"].to_s.strip.downcase
        problems[:final_state] = "estado final fora da lista (quitado ou parcial)" unless final_state.empty? || FINAL_STATES.key?(final_state)
        Record.new(position: position, extra: extra, short: short, raw: values, document: Document.normalize(values["documento"]), paid_on: paid_on, amount_cents: cents,
                   payment_method: method, final_state: FINAL_STATES[final_state], format_problems: problems)
      end
  end
end
