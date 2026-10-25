# Políticas, prazo máximo e alçada das promessas (10, R189, R190, R206): a permissão 14 (alterar políticas financeiras), no credor.
class PromiseSettingPolicy < ApplicationPolicy
  def show? = user.permitted_anywhere?("change_financial_policies")
  def update? = permitted?("change_financial_policies")

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with("change_financial_policies"))
  end
end
