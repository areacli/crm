# Quebra as promessas abertas vencidas e encerra as pendentes sem aprovação de um credor (10, R193, R197).
class PromisesDailyJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(tenant) = Promises::Daily.new(tenant).call
end
