# Conferência e confirmação do lote de distribuição em segundo plano (14, R316), com o aviso pelo WebSocket quando termina.
class DistributionBatchJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(batch, step)
    step == "confirm" ? Distributions::BatchConfirmer.new(batch).call : Distributions::BatchChecker.new(batch).call
  rescue StandardError
    batch.update!(status: "failed") unless batch.reload.confirmed?
    raise
  ensure
    DistributionsChannel.broadcast_to(batch.tenant, { event: "distribution-batch-ready" })
    Live.publish("lotes", batch.id, tenant_id: batch.tenant_id)
  end
end
