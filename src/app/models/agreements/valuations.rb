module Agreements
  # O valor atualizado dos títulos de acordo em cobrança (11, R225, R228): o que falta da face mais os encargos de atraso dos parâmetros que o acordo congelou, para a lista,
  # o painel e a ficha. Os juros do parcelamento ainda não corridos não entram (N7). Linhas de `bill_valuations`; o recálculo comum não lê estes títulos.
  module Valuations
    module_function

    # [[bill_id, tenant_id, principal, principal corrigido, multa, juros, honorários, total, data]] dos títulos de acordo vencidos.
    def rows(tenant, today)
      bills = Bill.where(tenant_id: tenant.id, status: "active").where.not(kind: "common").where(due_date: ...today).to_a
      LedgerLoader.new(tenant, today: today).call(bills).filter_map do |bill_id, ledger|
        parts, = ledger.balance_parts(today)
        breakdown = ledger.late_breakdown(today)
        face = parts.except("late").values.sum
        total = face + parts.fetch("late", 0)
        next if total.zero?

        [ bill_id, tenant.id, face, face, breakdown.fetch("fine", 0), breakdown.fetch("interest", 0), breakdown.fetch("fees", 0) + breakdown.fetch("correction", 0), total, today ]
      end
    end
  end
end
