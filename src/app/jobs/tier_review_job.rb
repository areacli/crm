# Conferência do impacto em segundo plano (13, R272, revisão 3): calcula e avisa a tela pelo WebSocket.
class TierReviewJob < ApplicationJob
  queue_as :default

  def perform(id) = Tiers::Review.compute(id)
end
