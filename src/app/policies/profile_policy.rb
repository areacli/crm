# Perfis: a permissão 11 (gerenciar perfis), no credor do perfil.
class ProfilePolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("manage_profiles")
  def show? = permitted?("manage_profiles")
  def create? = permitted?("manage_profiles")
  def new? = index?
  def update? = permitted?("manage_profiles")
  # Perfil em uso não se apaga (R35): a regra é do gerenciador, que responde "perfil em uso por N usuários".
  def destroy? = permitted?("manage_profiles")

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with("manage_profiles"))
  end
end
