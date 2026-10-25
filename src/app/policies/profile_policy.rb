# Perfis: a permissão 11 (gerenciar perfis), no credor do perfil.
class ProfilePolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("manage_profiles")
  def show? = permitted?("manage_profiles")
  def create? = permitted?("manage_profiles")
  def update? = permitted?("manage_profiles")
  def destroy? = permitted?("manage_profiles") && record.memberships.none?

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with("manage_profiles"))
  end
end
