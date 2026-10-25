# Contas de pagamento: a permissão 14 (alterar políticas financeiras) no credor da conta (12, R267). Conta de credor sem acesso responde
# como "não encontrada".
class PaymentAccountPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("change_financial_policies")
  def new? = index?
  def create? = permitted?("change_financial_policies")
  def update? = create?
  def destroy? = create?
  def test? = create?

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with("change_financial_policies"))
  end
end
