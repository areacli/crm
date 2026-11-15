# Conferência do impacto da régua em segundo plano (21, R442): termina à vista, com sucesso ou com o motivo, e avisa no sino quem pediu.
class CadenceReviewJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(tenant, token, requested_by: nil)
    ImpactReview.run(Cadences::Review, tenant, token, user: requested_by, where: I18n.t("impact_review.cadence", tenant: tenant.name))
  ensure
    CadencesChannel.broadcast_to(tenant, { event: "cadence-review-ready" })
  end
end
