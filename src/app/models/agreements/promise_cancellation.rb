module Agreements
  # O aceite cancela as promessas abertas ou pendentes dos títulos do acordo (11, R222, DA11), com o motivo "títulos renegociados em acordo", sem exigir a permissão 15
  # (RP4) e sem deixar carência nos títulos: a promessa foi substituída, não encerrada (R235, 10 R188).
  module PromiseCancellation
    REASON = "títulos renegociados em acordo".freeze

    module_function

    def call(agreement, actor) = cancel(agreement.agreement_bills.select(:bill_id), actor, REASON)

    # Cancela as promessas abertas ou pendentes que prendem os títulos (`bill_ids`: lista ou subconsulta), sem carência, com o motivo dado: o aceite (R222), a abertura da reversão
    # (R239, "acordo em reversão") e o título de acordo cancelado (R251).
    def cancel(bill_ids, actor, reason)
      promise_ids = PaymentPromiseBill.where(bill_id: bill_ids, held: true, removed_at: nil).select(:promise_id)
      PaymentPromise.where(id: promise_ids, state: PaymentPromise::HOLDING).lock.each do |promise|
        promise.close!("canceled", reason: reason, actor: actor)
        promise.update!(grace_free: true)
      end
    end
  end
end
