# Distribuição de um credor (14, R316): quem distribui (permissão 19) assina; o evento diz que a conferência ou a confirmação de um lote terminou.
class DistributionsChannel < ApplicationCable::Channel
  def subscribed
    tenant = Tenant.find_by(id: params[:tenant_id])
    return reject unless tenant && current_user&.permitted?("distribute_portfolio", tenant)

    stream_for tenant
  end
end
