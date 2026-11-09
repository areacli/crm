# Conferência do impacto (step "review") e recálculo depois de confirmar (step "apply") do enquadramento da distribuição (14, R343, R345), em
# segundo plano, com o aviso pelo WebSocket.
class DistributionRulesJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(tenant, actor = nil, token: nil, requested_by: nil)
    if token
      ImpactReview.run(DistributionRules::Review, tenant, token, user: requested_by, where: I18n.t("impact_review.distribution", tenant: tenant.name))
    else
      DistributionRules::Recalculation.new(tenant, actor: actor).apply
    end
  ensure
    DistributionsChannel.broadcast_to(tenant, { event: token ? "distribution-review-ready" : "distribution-rules-changed" })
  end
end
