# Configuração do credor (faixas de atraso e tratamento do a vencer): a permissão 4 (alterar configuração), no credor.
class TenantSettingPolicy < ApplicationPolicy
  def show? = user.permitted_anywhere?("change_settings")
  def update? = permitted?("change_settings")

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with("change_settings"))
  end
end
