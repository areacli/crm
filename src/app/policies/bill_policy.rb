# Título: o histórico dele (versões do valor, pagamentos, estornos e divergências) abre para quem consulta a carteira, no credor do título (R100).
class BillPolicy < ApplicationPolicy
  def show? = permitted?("view_portfolio")

  class Scope < Scope
    def resolve = scope.visible_to(user, "view_portfolio")
  end
end
