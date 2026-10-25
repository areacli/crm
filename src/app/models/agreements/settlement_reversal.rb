module Agreements
  # O estorno do pagamento da quitação antecipada (11, R230, AE9, AF4): o pagamento com o número do acordo quitou os títulos pelo valor calculado, dispensando os juros do parcelamento que
  # ainda não correram. Estornado no todo ou em parte, o que sobra é comparado de novo com o valor calculado e a tolerância de valor dos títulos de acordo: se ainda quita, a quitação se
  # mantém e a diferença vira abatimento por tolerância (AE9); senão ela se desfaz: os títulos voltam ao que eram antes dela, com os juros cheios do parcelamento, o cálculo perde a
  # validade e o que não foi estornado vira pagamento comum dos títulos de acordo, com a data do pagamento original, do mais antigo para o mais novo, com o desconto de antecipação
  # nos títulos a vencer (DA35) e o excedente pela DA9. O acordo reabre e o arquivo leva "quitado reaberto".
  module SettlementReversal
    module_function

    # `payment`: o pagamento da quitação; `cents`: o valor estornado; `on`: a data da ação de estorno.
    def call(payment, cents, on)
      agreement = Agreement.find(payment.agreement_id)
      bills = Bill.where(id: PaymentAllocation.where(payment_id: payment.id).select(:bill_id)).order(:due_date, :id).to_a
      cash = PaymentAllocation.where(payment_id: payment.id).sum(:amount_cents)
      calculated = cash + Abatement.where(payment_id: payment.id, kind: %w[tolerance creditor]).sum(:amount_cents)
      tolerance = Policies.tolerance_of(agreement.tolerance_spec, calculated)
      remaining = cash - cents
      if remaining >= calculated - tolerance
        keep_settlement(payment, bills, cents)
      else
        undo_settlement(agreement, payment, bills, remaining, on)
      end
      agreement.settlements.where(expired_at: nil).update_all(expired_at: Time.current)
    end

    # A quitação se mantém: o estornado sai da alocação, do último título para o primeiro, e vira abatimento por tolerância (o título continua pago).
    def keep_settlement(payment, bills, cents)
      left = cents
      bills.reverse_each do |bill|
        break unless left.positive?

        before = bill.paid_cents
        result = AllocationUndo.call(payment, bill.reload, cents: left)
        next if result.cash.zero?

        left -= result.cash
        result.parts.each { |component, part| Abatement.create!(tenant_id: payment.tenant_id, payment: payment, bill: bill, kind: "tolerance", component: component, amount_cents: part) }
        bill.update!(paid_cents: before, status: "paid", paid_on: bill.paid_on || payment.paid_on)
      end
    end

    # A quitação se desfaz: tudo o que o pagamento fez nos títulos é desfeito e o que sobra do dinheiro paga os títulos como pagamento comum, na data do pagamento original.
    def undo_settlement(agreement, payment, bills, remaining, on)
      bills.each { |bill| AllocationUndo.call(payment, bill.reload, abatements: true) }
      left = [ remaining, 0 ].max
      agreement.titles.where(status: "active").each do |bill|
        break unless left.positive?

        outcome = TitleSettler.pay!(payment, bill.reload, left, payment.paid_on, tolerance: agreement.tolerance_spec)
        left -= outcome.applied
      end
      CreditBook.add!(bills.first.contract_id, left, reason: "excess", payment_id: payment.id, agreement_id: agreement.id, note: "quitação desfeita") if left.positive?
      ClosedReopening.reopen_after_settlement!(agreement, on) if agreement.state_settled?
    end
  end
end
