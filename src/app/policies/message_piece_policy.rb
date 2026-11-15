# Peças da mensageria (21, R446): com a "configurar régua" (24) até a mensageria ter permissão própria.
class MessagePiecePolicy < ApplicationPolicy
  KEY = CadencePolicy::KEY

  def index? = user.permitted_anywhere?(KEY)
  def new? = index?
  def create? = permitted?(KEY)
  def update? = create?
  def destroy? = create?

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with(KEY))
  end
end
