# Correção de índice do credor (08, R145, R146, R157): a permissão 14, no credor da correção.
class IndexAdjustmentPolicy < ApplicationPolicy
  def create? = permitted?("change_financial_policies")
  def destroy? = create?
end
