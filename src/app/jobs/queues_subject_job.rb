# Recálculo do enquadramento da fila só dos sujeitos de um acionamento (15, R351), em segundo plano.
class QueuesSubjectJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(tenant, only) = Queues::Recalculation.new(tenant).apply(only: only)
end
