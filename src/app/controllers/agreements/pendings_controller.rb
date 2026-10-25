module Agreements
  # Acordos pendentes que o usuário pode aprovar (11, R216, R243): nos credores em que tem "negociar acordos", com os limites atuais dele cobrindo a proposta, e
  # nunca as que ele mesmo montou. A lista e o número do menu usam a mesma consulta. Refeita por evento do WebSocket, sem polling.
  class PendingsController < ApplicationController
    def index
      authorize Agreement, :index?
      scope = Agreements::Pending.for(Current.user)
      @tenants = Tenant.where(id: scope.distinct.pluck(:tenant_id)).order(:name).pluck(:name, :id)
      @several_tenants = @tenants.size > 1
      scope = scope.where(tenant_id: params[:tenant]) if params[:tenant].present?
      @agreements = scope.includes(:customer, :tenant, :user).order(:valid_until, :id).to_a
      @cable = Current.user.tenant_ids_with("negotiate_agreements").map { |id| { channel: "AgreementsChannel", tenant_id: id } }.to_json
      render partial: "agreements/pendings/result" if htmx_fragment?
    end
  end
end
