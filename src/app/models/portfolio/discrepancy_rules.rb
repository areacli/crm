module Portfolio
  # Regras da divergência de valor (05, R93 a R97) em duas formas que dão o mesmo resultado (o teste confere): fragmentos de SQL de LEITURA, para a
  # conferência contar e listar as divergências sobre todas as linhas da carga, e `evaluate`, em Ruby sobre o título, para a confirmação gravar. Os fragmentos esperam o título como `b` e o valor informado por `reported`. Nada é
  # interpolado a partir de entrada do usuário: só nomes de coluna e a política, que vem de um enum.
  module DiscrepancyRules
    module_function

    Outcome = Data.define(:effect, :balance_before_cents, :balance_after_cents, :excess_cents)

    # Título com pagamento aplicado ou pago (R93), em Ruby.
    def with_allocation?(bill) = bill.paid_cents.positive? || bill.paid?

    # O mesmo cálculo dos fragmentos de SQL abaixo, para um título e o valor informado na carga.
    def evaluate(bill, reported_cents, policy)
      keep = policy.to_s == "keep"
      before = bill.paid? ? 0 : [ bill.amount_cents - bill.paid_cents, 0 ].max
      effect =
        if bill.paid? then "record_only"
        elsif keep then "kept"
        elsif reported_cents <= bill.paid_cents then (bill.withdrawn? ? "returns_paid" : "becomes_paid")
        elsif reported_cents > bill.amount_cents then "balance_up"
        else "balance_down"
        end
      after = keep ? before : (bill.paid? ? 0 : [ reported_cents - bill.paid_cents, 0 ].max)
      excess = keep || bill.paid? ? [ bill.paid_cents - bill.amount_cents, 0 ].max : [ bill.paid_cents - reported_cents, 0 ].max
      Outcome.new(effect: effect, balance_before_cents: before, balance_after_cents: after, excess_cents: excess)
    end

    # Título com alocação (qualquer pagamento aplicado) ou pago (R93). Título sem alocação segue a R13, sem divergência.
    WITH_ALLOCATION = "(b.paid_cents > 0 or b.status = 'paid')".freeze

    # Efeito aplicado ao título (R94 a R97, R98). Título pago nunca é alterado pela carga (R96).
    def effect_sql(policy, reported)
      if policy.to_s == "keep"
        "case when b.status = 'paid' then 'record_only' else 'kept' end"
      else
        <<~SQL.squish
          case when b.status = 'paid' then 'record_only'
               when #{reported} <= b.paid_cents then (case when b.status = 'withdrawn' then 'returns_paid' else 'becomes_paid' end)
               when #{reported} > b.amount_cents then 'balance_up'
               else 'balance_down' end
        SQL
      end
    end

    # Saldo antes da carga: nunca negativo (R89); o título pago tem saldo zero por definição.
    def balance_before_sql = "(case when b.status = 'paid' then 0 else greatest(b.amount_cents - b.paid_cents, 0) end)"

    # Saldo depois da carga, pela política.
    def balance_after_sql(policy, reported)
      return balance_before_sql if policy.to_s == "keep"

      "(case when b.status = 'paid' then 0 else greatest(#{reported} - b.paid_cents, 0) end)"
    end

    # Excedente depois da carga (R90): o que o alocado passa do valor que vai valer.
    def excess_sql(policy, reported)
      return "greatest(b.paid_cents - b.amount_cents, 0)" if policy.to_s == "keep"

      "(case when b.status = 'paid' then greatest(b.paid_cents - b.amount_cents, 0) else greatest(b.paid_cents - #{reported}, 0) end)"
    end
  end
end
