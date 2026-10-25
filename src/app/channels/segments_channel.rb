# Aba Segmentos de um credor (08, R153): quem a vê no credor (permissão 4 ou 14) assina; o evento diz que o recálculo terminou.
class SegmentsChannel < ApplicationCable::Channel
  def subscribed
    tenant = Tenant.find_by(id: params[:tenant_id])
    return reject unless tenant && current_user && %w[change_settings change_financial_policies].any? { |permission| current_user.permitted?(permission, tenant) }

    stream_for tenant
  end
end
