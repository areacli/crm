module Payments
  # Converte o texto de um registro de estorno nos tipos do registro canônico (decisão 0031). Não recusa: o que não pôde ser convertido fica em
  # `format_problems`, e o validador decide.
  class ReversalRowDecoder
    Record = Data.define(:position, :extra, :short, :raw, :paid_on, :amount_cents, :format_problems)

    def decode(raw)
      values = raw.values
      problems = {}
      paid_on = BrDate.parse(values["data_estorno"])
      problems[:paid_on] = "data inválida" unless paid_on
      cents, money_problem = Money.parse_cents(values["valor"])
      problems[:amount] = money_problem if money_problem
      Record.new(position: raw.position, extra: raw.extra, short: raw.short, raw: values, paid_on: paid_on, amount_cents: cents, format_problems: problems)
    end
  end
end
