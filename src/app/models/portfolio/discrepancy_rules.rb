module Portfolio
  # Regras da divergência de valor (05, R93 a R97) escritas como fragmentos de SQL, para a conferência e a confirmação calcularem o mesmo
  # efeito, em lote, sobre as linhas da carga. Os fragmentos esperam o título como `b` e o valor informado por `reported`. Nada é
  # interpolado a partir de entrada do usuário: só nomes de coluna e a política, que vem de um enum.
  module DiscrepancyRules
    module_function

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
