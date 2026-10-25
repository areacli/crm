# Políticas de pagamento do credor: a permissão 14 (alterar políticas financeiras), no credor (R46, R46a, R62a, R64).
class PaymentSettingPolicy < ApplicationPolicy
  def show? = user.permitted_anywhere?("change_financial_policies")
  def update? = permitted?("change_financial_policies")

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with("change_financial_policies"))
  end
end
