module Promises
  # Aprovar e recusar a promessa pendente (R192). A política já conferiu a 7, a alçada e que não é quem registrou; aqui ficam as regras de dados.
  class Reviewer
    MAX_REASON = 300

    def initialize(actor) = @actor = actor

    def approve(promise)
      ApplicationRecord.transaction do
        promise.lock!
        refuse!(:not_pending) unless promise.state_pending?
        # R193: passado o prazo sem aprovação, a promessa termina como não aprovada.
        refuse!(:deadline_passed) if Date.current > promise.deadline
        promise.update!(state: "open", number: Numbering.next_for(promise.tenant_id), decided_by: @actor, decided_at: Time.current)
        Change.create!(tenant_id: promise.tenant_id, user: @actor, subject_type: "payment_promise", subject_id: promise.id, event: "approved", before: "pending", after: "open")
      end
      promise
    end

    def refuse(promise, reason)
      reason = reason.to_s.strip
      refuse!(:reason_required) if reason.empty?
      refuse!(:reason_too_long, max: MAX_REASON) if reason.length > MAX_REASON
      ApplicationRecord.transaction do
        promise.lock!
        refuse!(:not_pending) unless promise.state_pending?
        promise.update!(decided_by: @actor, decided_at: Time.current)
        promise.close!("refused", reason: reason, actor: @actor)
      end
      promise
    end

    private
      def refuse!(key, **options) = raise(Refused, I18n.t("promises.refused.#{key}", **options))
  end
end
