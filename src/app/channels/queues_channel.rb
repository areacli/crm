# Filas de um credor (15, R357): quem gerencia a fila (permissão 21) assina; o evento diz que algo mudou nas filas (recálculo, entrega,
# liberação), e a visão do gestor e a configuração refazem o trecho.
class QueuesChannel < ApplicationCable::Channel
  def subscribed
    tenant = Tenant.find_by(id: params[:tenant_id])
    return reject unless tenant && current_user&.permitted?("manage_queues", tenant)

    stream_for tenant
  end
end
