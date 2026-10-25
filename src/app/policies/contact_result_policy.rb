# Resultados de acionamento: "gerenciar resultados" (9) no credor do resultado (R66, R76). De credor sem acesso, responde "não encontrado".
class ContactResultPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("manage_contact_results")
  def new? = index?
  def create? = permitted?("manage_contact_results")
  def update? = create?

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with("manage_contact_results"))
  end
end
