# Conciliação diária dos pagamentos de um credor (12, parte D): ver `Payments::Reconciler`.
class PaymentReconciliationJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(tenant) = Payments::Reconciler.new(tenant).call
end
