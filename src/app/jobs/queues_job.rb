# Conferência do impacto (com `token`) e recálculo depois de confirmar (sem) do enquadramento da fila (15, R357), em segundo plano, com o aviso
# pelo WebSocket.
class QueuesJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(tenant, token: nil)
    token ? Queues::Review.compute(tenant, token) : Queues::Recalculation.new(tenant).call
  ensure
    QueuesChannel.broadcast_to(tenant, { event: token ? "queue-review-ready" : "queues-changed" })
  end
end
