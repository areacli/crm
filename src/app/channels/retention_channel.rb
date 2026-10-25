# Guarda de dados de um credor: só quem atende os direitos do titular nele (permissão 13, MT-3). O canal transmite um evento de invalidação
# pequeno ("retention-changed"); a página de guarda refaz os trechos com htmx.
class RetentionChannel < ApplicationCable::Channel
  def subscribed
    tenant = Tenant.find_by(id: params[:tenant_id])
    return reject unless tenant && current_user && current_user.permitted?("handle_data_subject_rights", tenant)

    stream_for tenant
  end
end
