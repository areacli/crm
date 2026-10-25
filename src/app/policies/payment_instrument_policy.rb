# Instrumentos de pagamento: ver os dados e baixar o PDF e o QR Code vale para quem consulta a carteira (permissão 1) no credor do instrumento (12,
# R275, MT-3). Instrumento de credor sem a permissão responde como "não encontrado", com o acesso recusado registrado (V10). Não há ação de emitir:
# a emissão é só por serviço (R270).
class PaymentInstrumentPolicy < ApplicationPolicy
  def show? = permitted?("view_portfolio")
  def pdf? = show?
  def qr_code? = show?

  class Scope < Scope
    def resolve = scope.where(tenant_id: user.tenant_ids_with("view_portfolio"))
  end
end
