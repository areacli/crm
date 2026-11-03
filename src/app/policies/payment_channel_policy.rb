# Métodos de recebimento (16, R373; antes "canais de recebimento", R45): cadastrar, editar e excluir o método vale a "alterar configuração" (4)
# no credor dele; a tela também abre para quem só tem a 14 (que cuida das integrações no detalhe de cada método). Método de credor sem acesso
# responde como "não encontrado".
class PaymentChannelPolicy < ApplicationPolicy
  VIEW = %w[change_settings change_financial_policies].freeze

  def index? = VIEW.any? { |key| user.permitted_anywhere?(key) }
  def new? = user.permitted_anywhere?("change_settings")
  def create? = permitted?("change_settings")
  def update? = permitted?("change_settings")
  # Apagar vale só a permissão; que o método tenha pagamento é regra do gerenciador, que responde com a mensagem escrita (R45).
  def destroy? = update?

  class Scope < Scope
    def resolve = scope.where(tenant_id: VIEW.flat_map { |key| user.tenant_ids_with(key) }.uniq)
  end
end
