# Tarefas das filas (21, R446; 15, revisão 3): com a "gerenciar fila" (21), como o resto da configuração das filas.
class QueueTaskPolicy < ApplicationPolicy
  KEY = "manage_queues".freeze

  def index? = user.permitted_anywhere?(KEY)
  def new? = index?
  def create? = permitted?(KEY)
  def update? = create?
  def destroy? = create?

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with(KEY))
  end
end
