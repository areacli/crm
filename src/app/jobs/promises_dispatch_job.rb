# Tarefa diária das promessas (10, R193, R197): enfileira uma execução por credor ativo, depois do recálculo do valor atualizado.
class PromisesDispatchJob < ApplicationJob
  queue_as :default

  def perform
    Tenant.where(active: true).find_each { |tenant| PromisesDailyJob.perform_later(tenant) }
  end
end
