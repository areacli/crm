# Conferência do impacto (step "review") e recálculo depois de confirmar (step "apply") do enquadramento da distribuição (14, R343, R345), em
# segundo plano, com o aviso pelo WebSocket.
class DistributionRulesJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(tenant, actor = nil, token: nil)
    token ? DistributionRules::Review.compute(tenant, token) : DistributionRules::Recalculation.new(tenant, actor: actor).apply
  ensure
    DistributionsChannel.broadcast_to(tenant, { event: token ? "distribution-review-ready" : "distribution-rules-changed" })
  end
end
