module Promises
  # Cancelamento da promessa aberta ou pendente, com motivo obrigatório (R200). Os títulos ficam livres, sujeitos à carência (R188), e os já pagos
  # pela promessa continuam pagos. A permissão 15 já foi conferida pela política, no credor da promessa.
  class Canceller
    MAX_REASON = 300

    def initialize(actor) = @actor = actor

    def cancel(promise, reason)
      reason = reason.to_s.strip
      raise Refused, I18n.t("promises.refused.cancel_reason_required") if reason.empty?
      raise Refused, I18n.t("promises.refused.reason_too_long", max: MAX_REASON) if reason.length > MAX_REASON

      ApplicationRecord.transaction do
        promise.lock!
        raise Refused, I18n.t("promises.refused.not_cancelable") unless promise.holding?

        promise.close!("canceled", reason: reason, actor: @actor)
      end
      promise
    end
  end
end
