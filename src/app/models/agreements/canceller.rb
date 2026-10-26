module Agreements
  # Cancelamento da proposta ainda não aceita, com motivo obrigatório (11, R218, DA33): qualquer usuário com "negociar acordos" no credor. Libera os títulos. A
  # substituição por outra proposta usa o mesmo caminho, com o motivo "substituída por ACD-...". O cancelamento do acordo aceito é a reversão (etapa 5).
  class Canceller
    MAX_REASON = 300

    def initialize(actor) = @actor = actor

    def cancel(agreement, reason, kind: "canceled")
      reason = reason.to_s.strip
      raise Refused, I18n.t("agreements.refused.cancel_reason_required") if reason.empty?
      raise Refused, I18n.t("agreements.refused.reason_too_long", max: MAX_REASON) if reason.length > MAX_REASON

      ApplicationRecord.transaction do
        agreement.lock!
        raise Refused, I18n.t("agreements.refused.not_cancelable") unless agreement.proposal?

        close(agreement, "canceled", reason, kind)
      end
      agreement
    end

    private
      def close(agreement, state, reason, kind)
        agreement.update!(state: state, reason: reason, closed_at: Time.current)
        agreement.agreement_bills.update_all(held: false)
        AgreementEvent.log!(agreement, kind, user: @actor, data: { "reason" => reason })
        Change.record!(tenant_id: agreement.tenant_id, user: @actor, subject_type: "agreement", subject_id: agreement.id, event: "state_changed", field: "state", before: "proposal", after: state, note: reason)
      end
  end
end
