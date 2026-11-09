# Conferência do impacto em segundo plano (design system, 7.2): termina à vista, com sucesso ou com o motivo, e avisa no sino quem pediu.
module ImpactReview
  module_function

  # `review` é o módulo da conferência, com `key` e `compute`; `where` diz o que foi conferido.
  def run(review, tenant, token, user:, where:)
    review.compute(tenant, token)
    Rails.cache.delete(failure_key(review, token))
    BackgroundNotice.finished(user, what: I18n.t("impact_review.name"), where: where)
  rescue StandardError => error
    refused = error.is_a?(Queues::Refused) || error.is_a?(Distributions::Refused)
    reason = refused ? error.message : I18n.t("impact_review.failed")
    Rails.cache.write(failure_key(review, token), reason, expires_in: 30.minutes)
    BackgroundNotice.failed(user, what: I18n.t("impact_review.name"), where: where, reason: reason)
    raise unless refused
  end

  def failure(review, token) = Rails.cache.read(failure_key(review, token))

  def failure_key(review, token) = "#{review.key(token)}:failure"
end
