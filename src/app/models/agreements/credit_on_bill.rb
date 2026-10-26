module Agreements
  # "Usar crédito" num título de acordo ou de estorno, pela ficha (11, R232b, AI2): o crédito disponível do contrato do título paga o título como um pagamento do canal do sistema, com a
  # data do uso. Em qualquer política, inclusive "só registrar"; em outro título comum, não. Nunca reativa acordo pela R236a (X4). O estorno da origem desse crédito reabre o título pela
  # parte, pela regra base, e essa parte nunca é abatida por mínimo (AC3, AD5).
  module CreditOnBill
    USABLE_KINDS = %w[agreement break reversal].freeze

    module_function

    def usable?(bill) = USABLE_KINDS.include?(bill.kind) && bill.active?

    # O quanto o título deve hoje, em centavos (o teto do uso).
    def due_cents(bill, today = Date.current) = LedgerLoader.new(bill.tenant, today: today).one(bill).due(today).total

    def use!(bill, cents, actor, today: Date.current)
      raise Refused, I18n.t("agreements.credit_use.invalid_amount") unless cents.to_i.positive?
      raise Refused, I18n.t("agreements.credit_use.not_usable") unless usable?(bill)

      ApplicationRecord.transaction do
        contract = bill.contract
        contract.lock!
        available = CreditBook.balance(contract.id)
        raise Refused, I18n.t("agreements.credit_use.above_available", available: Money.format(available)) if cents > available
        raise Refused, I18n.t("agreements.credit_use.above_due", due: Money.format(due_cents(bill, today))) if cents > due_cents(bill, today)

        agreement = bill.agreement || bill.origin_agreement
        payment = Payment.create!(tenant_id: bill.tenant_id, channel: CreditUse.channel_for(bill.tenant), identifier: "CRED-USO-#{SecureRandom.hex(5)}", document: bill.customer.document,
                                  bill_number: bill.number, bill: bill, paid_on: today, amount_cents: cents, payment_method: "other", status: "applied")
        outcome = TitleSettler.pay!(payment, bill, cents, today, tolerance: agreement&.tolerance_spec)
        raise Refused, I18n.t("agreements.credit_use.above_due", due: Money.format(due_cents(bill, today))) if outcome.applied.zero?

        payment.update!(applied_cents: outcome.applied)
        CreditBook.take!(contract.id, outcome.applied, kind: "used", reason: "used_on_title", user: actor, bill_id: bill.id, note: bill.number)
        Change.record!(tenant_id: bill.tenant_id, user: actor, subject_type: "bill", subject_id: bill.id, event: "credit_used", after: outcome.applied.to_s)
        Standing.refresh!(bill.agreement, today: today) if bill.agreement
        Broadcast.changed(bill.tenant, [ bill.customer_id ])
        outcome
      end
    end

    # O estorno da origem do crédito usado no título: o título reabre pela parte (a alocação do pagamento com crédito é desfeita do uso mais recente para o mais antigo).
    def undo!(entry, cents, _reversed_on)
      bill = Bill.find(entry.bill_id)
      left = cents
      channel = PaymentChannel.find_by(tenant_id: bill.tenant_id, code: CreditUse::CHANNEL_CODE)
      Payment.where(bill_id: bill.id, channel_id: channel&.id).order(id: :desc).each do |payment|
        break unless left.positive?

        left -= AllocationUndo.call(payment, bill.reload, cents: left).cash
      end
      bill.update!(composition: (bill.composition || {}).merge("no_minimum" => true)) if bill.ledgered?
      yield bill if block_given?
      bill
    end
  end
end
