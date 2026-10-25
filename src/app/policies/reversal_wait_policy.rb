# Estornos à espera do gestor (11, R233, AH2): "administrar acordos" (17) no credor do estorno. A lista mostra só os credores em que a pessoa a tem.
class ReversalWaitPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("administer_agreements")
  def decide? = permitted?("administer_agreements") && permitted?("view_portfolio")

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with("administer_agreements"))
  end
end
