# Segmentos e enquadramento de um credor (13): quem os vê no credor (permissão 4 ou 14) assina; os eventos dizem que o recálculo terminou ou que uma conferência ficou pronta.
class SegmentsChannel < ApplicationCable::Channel
  def subscribed
    tenant = Tenant.find_by(id: params[:tenant_id])
    return reject unless tenant && current_user && %w[change_settings change_financial_policies].any? { |permission| current_user.permitted?(permission, tenant) }

    stream_for tenant
  end
end
