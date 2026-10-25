# Clientes: a permissão 1 (consultar a carteira), no credor do cliente. Cliente de credor sem acesso responde como "não encontrado" (MT-5).
class CustomerPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("view_portfolio")
  def show? = permitted?("view_portfolio")
  # Editar o cadastro (contatos e nome): a 12 e a 1 (RP1), no credor do cliente (06, R113, R113a).
  def edit_registry? = permitted?("edit_customer_registry") && permitted?("view_portfolio") && !record.anonymized?
  # Exportar, anonimizar e reter (07, R140, R140a): a 13 e a 1 (RP1), no credor do cliente.
  def handle_rights? = permitted?("handle_data_subject_rights") && permitted?("view_portfolio")

  class Scope < Scope
    def resolve = scope.visible_to(user, "view_portfolio")
  end
end
