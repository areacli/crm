# Clientes: a permissão 1 (consultar a carteira), no credor do cliente. Cliente de credor sem acesso responde como "não encontrado" (MT-5).
class CustomerPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("view_portfolio")
  def show? = permitted?("view_portfolio")

  class Scope < Scope
    def resolve = scope.visible_to(user, "view_portfolio")
  end
end
