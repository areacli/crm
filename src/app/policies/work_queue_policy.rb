# Filas (15, R357): ver, configurar e liberar entregas com a permissão 21 (gerenciar fila), no credor da fila. De credor sem acesso, a
# resposta é "não encontrado" e a recusa fica registrada (R33). Pedir "Próximo" e devolver são da 7 (`QueueDeliveriesController`).
class WorkQueuePolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("manage_queues")
  def create? = permitted?("manage_queues")
  def update? = create?

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with("manage_queues"))
  end
end
