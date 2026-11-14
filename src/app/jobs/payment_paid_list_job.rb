# Uma passada da lista de pagos de uma integração (12, revisão 4, R284c): ver `Payments::PaidList`. Falha do fornecedor não se repete aqui: a passada
# seguinte cobre o mesmo período, porque a última passada da integração só avança no sucesso.
class PaymentPaidListJob < ApplicationJob
  queue_as :webhooks
  discard_on ActiveJob::DeserializationError

  def perform(account)
    Payments::PaidList.new(account).call
  rescue Payments::Providers::Error => error
    Rails.error.report(error, handled: true, context: { payment_account_id: account.id })
  end
end
