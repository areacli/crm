# Reprocessa os avisos de pagamento de um credor que falharam ou ficaram parados (12, parte D). Também roda na conciliação diária.
class ReprocessPaymentEventsJob < ApplicationJob
  queue_as :webhooks
  discard_on ActiveJob::DeserializationError

  def perform(tenant) = Payments::EventReprocessor.new(tenant).call
end
