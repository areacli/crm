# Tarefa diária dos acordos de um credor (11, R217): expira as propostas aprovadas sem aceite e encerra as pendentes sem aprovação. As etapas seguintes acrescentam a
# quebra, o crédito e o arquivo do dia.
class AgreementsDailyJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(tenant) = Agreements::Daily.new(tenant).call
end
