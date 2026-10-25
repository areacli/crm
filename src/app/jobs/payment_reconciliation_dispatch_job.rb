# Tarefa diária da conciliação de pagamentos (12, parte D): enfileira uma execução por credor que tem conta de pagamento. Agendada em config/schedule.yml.
class PaymentReconciliationDispatchJob < ApplicationJob
  queue_as :default

  def perform
    Tenant.where(active: true, id: PaymentAccount.select(:tenant_id)).find_each { |tenant| PaymentReconciliationJob.perform_later(tenant) }
  end
end
