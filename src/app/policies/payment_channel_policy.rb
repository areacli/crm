# Canais de recebimento: "alterar configuração" (4) no credor do canal (R45, R45a). Canal de credor sem acesso responde como "não encontrado".
class PaymentChannelPolicy < ApplicationPolicy
  def index? = user.permitted_anywhere?("change_settings")
  def new? = index?
  def create? = permitted?("change_settings")
  def update? = permitted?("change_settings")
  # Apagar vale só a permissão; que o canal tenha pagamento é regra do gerenciador, que responde com a mensagem escrita (R45).
  def destroy? = update?

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with("change_settings"))
  end
end
