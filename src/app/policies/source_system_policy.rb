# Sistemas do credor (17, R396 a R399, R410): ver, criar, editar, pausar e excluir valem a "configurar integração" (23) no credor do sistema
# (R427). Sistema de credor sem acesso responde como "não encontrado". Quem importa não passa por aqui: vê só o nome dos sistemas, no envio.
class SourceSystemPolicy < ApplicationPolicy
  KEY = "configure_integration".freeze

  def index? = user.permitted_anywhere?(KEY)
  def new? = index?
  def create? = permitted?(KEY)
  def update? = permitted?(KEY)
  # Excluir vale só a permissão; que o sistema tenha importação é regra do modelo, que responde com a mensagem escrita (R399).
  def destroy? = update?

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with(KEY))
  end
end
