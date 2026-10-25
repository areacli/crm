module Agreements
  # O crédito que cobre atraso de acordo ativo (11, R232b, N17): enquanto cobrir, não se transfere nem se usa em outro lugar. Vale com o intervalo congelado aberto no acordo (a
  # tarefa diária o abre quando o crédito disponível cobre a amortização e os juros do parcelamento em atraso, na política "suspende a quebra").
  module CreditShield
    module_function

    # Centavos do crédito disponível do contrato que estão protegidos.
    def protected_cents(contract, today: Date.current)
      agreements = Agreement.where(id: AgreementBill.where(contract_id: contract.id).select(:agreement_id), state: %w[active_on_time active_late]).select { |item| open_credit_span?(item) }
      return 0 if agreements.empty?

      due = agreements.sum { |agreement| covered_due(agreement, contract, today) }
      [ due, contract.credit_cents ].min
    end

    def open_credit_span?(agreement) = agreement.frozen_spans.any? { |span| span["kind"] == "credit" && span["to"].nil? }

    # A amortização e os juros do parcelamento em atraso dos títulos do acordo no contrato (o que o crédito cobre, sem os encargos de atraso).
    def covered_due(agreement, contract, today)
      overdue = agreement.titles.where(status: "active", contract_id: contract.id).select { |bill| today > agreement.deadline_for(bill, agreement.tolerance_days) }
      return 0 if overdue.empty?

      ledgers = LedgerLoader.new(agreement.tenant, today: today).call(overdue)
      overdue.sum { |bill| ledgers.fetch(bill.id).due(today).parts.except("late").values.sum }
    end
  end
end
