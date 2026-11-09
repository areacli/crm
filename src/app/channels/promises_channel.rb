# Avisos de promessa: a lista de pendentes e o painel assinam o credor, a ficha assina o cliente. Só quem consulta a carteira no credor (MT-3).
# O canal transmite um evento de invalidação pequeno ("promises-changed"); a aba da casca refaz o trecho (`data-spa-vivo`).
class PromisesChannel < ApplicationCable::Channel
  def subscribed
    stream = params[:customer_id].present? ? Customer.find_by(id: params[:customer_id]) : Tenant.find_by(id: params[:tenant_id])
    tenant = stream.is_a?(Customer) ? stream.tenant : stream
    return reject unless tenant && current_user && PaymentPromisePolicy.new(current_user, PaymentPromise.new(tenant: tenant)).watch?

    stream_for stream
  end
end
