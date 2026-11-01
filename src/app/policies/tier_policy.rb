# Enquadramento financeiro do credor (13, R276): ver, com a permissão 4 ou 14; mudar (incluir, tirar, mover, regras), só com a 14 no credor do
# item. O "Demais" não se move nem se tira, mas tem regras (R265).
class TierPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("change_settings") || user.permitted_anywhere?("change_financial_policies")
  def create? = permitted?("change_financial_policies")
  def update? = create?
  def destroy? = create? && !record.catch_all?
  def rearrange? = destroy?

  class Scope < Scope
    def resolve = scope.where(tenant_id: (user.tenant_ids_with("change_settings") + user.tenant_ids_with("change_financial_policies")).uniq)
  end
end
