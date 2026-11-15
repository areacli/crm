# Réguas (21, R445): ver, criar, editar, ligar e desligar, e ver rodadas e comandos valem a "configurar régua" (24) no credor da régua. Régua de
# credor sem acesso responde como "não encontrado", e a recusa fica registrada (R33). O usuário de operação não configura réguas.
class CadencePolicy < ApplicationPolicy
  KEY = "configure_cadence".freeze

  def index? = user.permitted_anywhere?(KEY)
  def show? = permitted?(KEY)
  def new? = index?
  def create? = permitted?(KEY)
  def update? = create?
  def destroy? = create?

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with(KEY))
  end
end
