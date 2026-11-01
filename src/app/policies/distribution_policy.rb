# Distribuição (14, R311, R326): a permissão 19 (distribuir carteira), no credor da distribuição.
class DistributionPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("distribute_portfolio")
  def create? = permitted?("distribute_portfolio")
  # Os formulários de distribuir e de lote abrem sem credor escolhido: basta a 19 em algum; o `create?` confere a do credor escolhido.
  def new? = index?
  def update? = permitted?("distribute_portfolio")

  class Scope < Scope
    def resolve = scope.visible_to(user, "distribute_portfolio")
  end
end
