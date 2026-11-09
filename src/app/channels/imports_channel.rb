# Andamento das importações de um credor: só quem tem alguma permissão de importação nele (MT-3). O canal transmite eventos de
# invalidação pequenos; a aba da casca refaz o trecho (`data-spa-vivo`).
class ImportsChannel < ApplicationCable::Channel
  def subscribed
    tenant = Tenant.find_by(id: params[:tenant_id])
    return reject unless tenant && current_user && ImportPolicy.new(current_user, Import.new(tenant: tenant)).watch?

    stream_for tenant
  end
end
