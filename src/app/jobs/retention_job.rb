# Guarda de dados de um credor (07, R137): anonimiza quem passou do prazo de guarda e não está retido. Fila `default`.
class RetentionJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(tenant)
    Titular::RetentionRun.new(tenant).call
  end
end
