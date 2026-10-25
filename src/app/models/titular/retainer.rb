module Titular
  # Retenção (07, R138): o gestor marca o cliente para a tarefa diária não o anonimizar, com motivo, e desfaz do mesmo jeito. Reter um
  # anonimizado, reter quem já está retido e desfazer a retenção de quem não está são recusados.
  class Retainer
    def initialize(actor) = @actor = actor

    def retain(customer, reason)
      reason = clean(reason)
      ApplicationRecord.transaction do
        customer.lock!
        raise Refused, I18n.t("titular.retention.anonymized") if customer.anonymized?
        raise Refused, I18n.t("titular.retention.already") if customer.retained?

        customer.update!(retained_at: Time.current, retained_reason: reason, retained_by: @actor)
        log(customer, "retained", reason)
      end
      Broadcast.changed(customer.tenant)
    end

    def release(customer, reason)
      reason = clean(reason)
      ApplicationRecord.transaction do
        customer.lock!
        raise Refused, I18n.t("titular.retention.not_retained") unless customer.retained?

        customer.update!(retained_at: nil, retained_reason: nil, retained_by: nil)
        log(customer, "retention_released", reason)
      end
      Broadcast.changed(customer.tenant)
    end

    private
      def clean(reason)
        reason = reason.to_s.strip
        raise Refused, I18n.t("titular.retention.reason_required") if reason.empty?

        reason[0, 300]
      end

      def log(customer, event, reason)
        Change.create!(tenant_id: customer.tenant_id, user: @actor, subject_type: "customer", subject_id: customer.id, event: event, note: reason, origin: "screen")
      end
  end
end
