# Vínculos (usuários de um credor): a permissão 10 (gerenciar usuários), no credor do vínculo. Ninguém altera o próprio vínculo (PD7).
class MembershipPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("manage_users")
  def show? = permitted?("manage_users")
  def create? = permitted?("manage_users")
  def new? = index?
  def update? = permitted?("manage_users") && record.user_id != user.id

  # Nome e senha são da pessoa (R36a): só de quem não atua em outro credor.
  def edit_personal? = update? && record.personal_data_editable?

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with("manage_users"))
  end
end
