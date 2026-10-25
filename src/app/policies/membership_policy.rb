# Vínculos (usuários de um credor): a permissão 10 (gerenciar usuários), no credor do vínculo.
class MembershipPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("manage_users")
  def show? = permitted?("manage_users")
  def create? = permitted?("manage_users")
  def update? = permitted?("manage_users") && record.user_id != user.id

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with("manage_users"))
  end
end
