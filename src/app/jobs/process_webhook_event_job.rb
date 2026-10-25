# Baixa o pagamento de um evento de webhook em segundo plano, na fila `webhooks`. O evento já foi autenticado e guardado (idempotência por
# canal + identificador do evento), então reexecutar o job é inofensivo: só processa o que ainda está "recebido".
class ProcessWebhookEventJob < ApplicationJob
  queue_as :webhooks
  discard_on ActiveJob::DeserializationError

  retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, error|
    event = job.arguments.first
    event.update!(status: :failed, outcome: error.class.name.demodulize, processed_at: Time.current)
    Rails.error.report(error, handled: true, context: { webhook_event_id: event.id })
  end

  def perform(event)
    Payments::WebhookProcessor.new.run(event)
  end
end
