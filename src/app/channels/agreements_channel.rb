# Avisos de acordo: a lista de acordos e a de pendentes assinam o credor, a ficha assina o cliente. Só quem negocia acordos no credor (MT-3) e consulta a
# carteira. O canal transmite um evento de invalidação pequeno ("agreements-changed"); a tela refaz o trecho com htmx.
class AgreementsChannel < ApplicationCable::Channel
  def subscribed
    stream = params[:customer_id].present? ? Customer.find_by(id: params[:customer_id]) : Tenant.find_by(id: params[:tenant_id])
    tenant = stream.is_a?(Customer) ? stream.tenant : stream
    return reject unless tenant && current_user && AgreementPolicy.new(current_user, Agreement.new(tenant: tenant)).watch?

    stream_for stream
  end
end
