# Operações do lado do credor (14, R306, R307, R310): a permissão 18 (gerenciar operações), no credor do credenciamento.
class AccreditationPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("manage_operations")
  def show? = permitted?("manage_operations")
  def create? = permitted?("manage_operations")
  # O formulário de credenciar abre sem credor escolhido: basta a 18 em algum credor; o `create?` confere a do credor escolhido.
  def new? = index?
  def update? = permitted?("manage_operations")
  # Dar e tirar vínculos: a 18, ou a 10 (gerenciar usuários) do credor (R310).
  def link? = permitted?("manage_operations") || permitted?("manage_users")

  class Scope < Scope
    def resolve = scope.visible_to(user, "manage_operations")
  end
end
