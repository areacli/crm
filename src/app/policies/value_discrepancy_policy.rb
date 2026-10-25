# Divergências de valor: a permissão 6 (confirmar pagamentos), no credor da divergência (R99, MT-3, MT-5). A lista mistura os credores em que a
# pessoa a tem.
class ValueDiscrepancyPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("confirm_payments")
  def show? = permitted?("confirm_payments")
  def create? = show?

  class Scope < Scope
    def resolve = scope.visible_to(user, "confirm_payments")
  end
end
