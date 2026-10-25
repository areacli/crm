# Processa um aviso de fornecedor de pagamento na fila `webhooks` (12, parte D). Consulta o fornecedor antes de atualizar (R283). Tenta de novo nas falhas
# (rede, fornecedor fora do ar); esgotadas as tentativas, o aviso fica `failed` com o motivo, e a reprocessagem diária o retoma.
class ProcessPaymentEventJob < ApplicationJob
  queue_as :webhooks
  discard_on ActiveJob::DeserializationError

  retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, error|
    event = job.arguments.first
    reason = error.is_a?(Payments::Providers::Error) ? error.message : error.class.name.demodulize
    event.finish!(:failed, reason)
    Rails.error.report(error, handled: true, context: { payment_event_id: event.id })
  end

  def perform(event) = Payments::EventProcessor.new.run(event)
end
