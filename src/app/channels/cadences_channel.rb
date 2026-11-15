# Réguas (21): a conferência pronta, a mudança confirmada e o fim de cada rodada chegam às telas abertas como evento de invalidação; a tela refaz
# o trecho, sem polling. Só para quem tem "configurar régua" (24) no credor.
class CadencesChannel < ApplicationCable::Channel
  def subscribed
    tenant = Tenant.find_by(id: params[:tenant_id])
    return reject unless tenant && current_user&.permitted?(CadencePolicy::KEY, tenant)

    stream_for tenant
  end
end
