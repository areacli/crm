module Agreements
  # Paga um título com um pagamento já criado, fora da confirmação de arquivo (11, R232b, R239): "Usar crédito" na ficha, a alocação do crédito aguardando alocação, a reaplicação
  # das liquidações na desistência da reversão. Título de acordo, da quebra ou de estorno: pelo `Ledger` (encargos de atraso, juros do parcelamento e composição, R227). Título comum:
  # pela baixa por componente da 09 (R226). Grava as alocações, os abatimentos e o estado do título; o excedente (acima do devido) volta a quem chamou.
  module TitleSettler
    Outcome = Data.define(:applied, :excess, :settled, :abatements)

    module_function

    # `date`: a data da liquidação (para encargos, tolerância e quebra); `tolerance`: a tolerância de valor dos títulos de acordo, congelada no acordo.
    def pay!(payment, bill, amount, date, tolerance: nil, early: true, ledger: nil)
      bill.lock!
      return Outcome.new(0, amount, false, []) unless bill.active? || bill.scheduled?

      bill.ledgered? ? pay_ledgered(payment, bill, amount, date, tolerance, early, ledger) : pay_common(payment, bill, amount, date)
    end

    def pay_ledgered(payment, bill, amount, date, tolerance, early, ledger = nil)
      ledger ||= LedgerLoader.new(bill.tenant, today: [ date, Date.current ].max).one(bill)
      ledger.without_early_discount! unless early
      result = TitlePayment.call(ledger, date: date, amount: amount, tolerance: tolerance)
      return Outcome.new(0, amount, false, []) if result.parts.empty? && result.abatements.empty?

      result.parts.each { |component, cents| PaymentAllocation.create!(payment: payment, bill: bill, component: component, amount_cents: cents) }
      result.abatements.each do |kind, parts|
        parts.each { |component, cents| Abatement.create!(tenant_id: payment.tenant_id, payment: payment, bill: bill, kind: kind, component: component, amount_cents: cents) }
      end
      paid = bill.paid_cents + result.face_covered
      done = result.settled
      bill.update!(paid_cents: paid, status: (done ? "paid" : bill.status), paid_on: (done ? date : bill.paid_on))
      Outcome.new(result.applied, result.excess, done, result.abatements)
    end

    def pay_common(payment, bill, amount, date)
      setting = bill.tenant.setting
      settlement = Charges::Settlement.for(bill.tenant, today: [ date, Date.current ].max)
      settlement&.preload([ bill.id ])
      balance = [ bill.amount_cents - bill.paid_cents, 0 ].max
      due = settlement&.due(bill.id, date, balance)
      result = Payments::Allocation.call(setting, bill_amount: bill.amount_cents, status: bill.status, paid: bill.paid_cents, amount: amount, due: due)
      result.components.each { |component, cents| PaymentAllocation.create!(payment: payment, bill: bill, component: component, amount_cents: cents) if cents.positive? }
      result.abatement.each { |component, cents| Abatement.create!(tenant_id: payment.tenant_id, payment: payment, bill: bill, kind: result.abatement_kind, component: component, amount_cents: cents) }
      bill.update!(paid_cents: bill.paid_cents + result.paid_principal, status: (result.settled ? "paid" : bill.status), paid_on: (result.settled ? date : bill.paid_on))
      Outcome.new(result.applied, result.credit, result.settled, [])
    end
  end
end
