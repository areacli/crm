# Arquivo de acordos (11, R244, R245): exportar e baixar exige "administrar acordos" (17) no credor, e a lista mostra só os credores em que o usuário a tem.
class AgreementExportPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("administer_agreements")
  def create? = administers?
  def show? = administers?

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with("administer_agreements"))
  end

  private
    def administers? = permitted?("administer_agreements") && permitted?("view_portfolio")
end
