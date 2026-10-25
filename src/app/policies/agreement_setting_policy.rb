# Parâmetros, variáveis, limites e políticas dos acordos (11, R207, R207a, R209, R246): só a permissão 14 (alterar políticas financeiras), no credor.
class AgreementSettingPolicy < ApplicationPolicy
  def show? = user.permitted_anywhere?("change_financial_policies")
  def update? = permitted?("change_financial_policies")

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with("change_financial_policies"))
  end
end
