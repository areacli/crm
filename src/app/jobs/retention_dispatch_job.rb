# Agendado todo dia às 3h de Brasília (config/schedule.yml): enfileira uma execução de guarda por credor ativo (R137a, MT-19). Cada credor tem
# o seu job, e a falha de um não impede os outros.
class RetentionDispatchJob < ApplicationJob
  queue_as :default

  def perform
    Tenant.where(active: true).find_each { |tenant| RetentionJob.perform_later(tenant) }
  end
end
