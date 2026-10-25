module Agreements
  # Aprovar e recusar a proposta pendente (11, R216): quem tem "negociar acordos" no credor e cujos limites atuais cobririam a proposta, nunca quem a montou
  # (a política já conferiu); aqui ficam as regras de dados. Vale a primeira gravação entre aprovar e recusar.
  class Reviewer
    MAX_REASON = 300

    def initialize(actor) = @actor = actor

    def approve(agreement, today: Date.current)
      ApplicationRecord.transaction do
        agreement.lock!
        refuse!(:not_pending) unless agreement.state_pending?
        # R217: passada a validade sem aprovação, a proposta termina como não aprovada.
        refuse!(:validity_passed) if agreement.expired_on?(today)
        agreement.update!(state: "approved", decided_by: @actor, decided_at: Time.current)
        AgreementEvent.log!(agreement, "approved", user: @actor)
        Change.create!(tenant_id: agreement.tenant_id, user: @actor, subject_type: "agreement", subject_id: agreement.id, event: "approved", before: "pending", after: "approved")
      end
      agreement
    end

    def refuse(agreement, reason)
      reason = reason.to_s.strip
      refuse!(:reason_required) if reason.empty?
      refuse!(:reason_too_long, max: MAX_REASON) if reason.length > MAX_REASON
      ApplicationRecord.transaction do
        agreement.lock!
        refuse!(:not_pending) unless agreement.state_pending?
        agreement.update!(state: "refused", reason: reason, decided_by: @actor, decided_at: Time.current, closed_at: Time.current)
        agreement.agreement_bills.update_all(held: false)
        AgreementEvent.log!(agreement, "refused", user: @actor, data: { "reason" => reason })
        Change.create!(tenant_id: agreement.tenant_id, user: @actor, subject_type: "agreement", subject_id: agreement.id, event: "state_changed", field: "state", before: "pending", after: "refused", note: reason)
      end
      agreement
    end

    private
      def refuse!(key, **options) = raise(Refused, I18n.t("agreements.refused.#{key}", **options))
  end
end
