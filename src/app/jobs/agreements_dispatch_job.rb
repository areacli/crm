# Tarefa diária dos acordos (11, R217; O8): enfileira uma execução por credor ativo, depois do recálculo do valor atualizado.
class AgreementsDispatchJob < ApplicationJob
  queue_as :default

  def perform
    Tenant.where(active: true).find_each { |tenant| AgreementsDailyJob.perform_later(tenant) }
  end
end
