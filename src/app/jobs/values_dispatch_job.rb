# Um recálculo do valor atualizado por credor ativo (09, R173, MT-19): depois de uma busca manual dos índices, que vale para todos os credores.
class ValuesDispatchJob < ApplicationJob
  queue_as :default

  def perform
    Tenant.where(active: true).find_each { |tenant| ValuesRecalculationJob.enqueue_for(tenant, reason: "índices") }
  end
end
