# Avisos de acionamento: a lista assina o credor, a ficha assina o cliente (para refazer o histórico só quando é o dela). Só quem consulta a
# carteira no credor (MT-3). O canal transmite um evento de invalidação pequeno ("contact-attempts-changed"); a tela refaz o trecho com htmx.
class ContactAttemptsChannel < ApplicationCable::Channel
  def subscribed
    stream = params[:customer_id].present? ? Customer.find_by(id: params[:customer_id]) : Tenant.find_by(id: params[:tenant_id])
    tenant = stream.is_a?(Customer) ? stream.tenant : stream
    return reject unless tenant && current_user && ContactAttemptPolicy.new(current_user, ContactAttempt.new(tenant: tenant)).watch?

    stream_for stream
  end
end
