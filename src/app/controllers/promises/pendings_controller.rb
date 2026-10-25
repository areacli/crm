module Promises
  # Lista das promessas pendentes que o usuário pode aprovar (10, R192, R204): mistura os credores em que ele pode aprovar, com a coluna Credor quando são mais
  # de um, o cliente que prometeu e o contrato, e um filtro opcional de credor sem estado guardado (MTD2). Refeita por evento do WebSocket, sem polling.
  class PendingsController < ApplicationController
    def index
      authorize PaymentPromise, :index?
      scope = Promises::Pending.for(Current.user)
      @tenant_ids = scope.distinct.pluck(:tenant_id)
      @tenants = Tenant.where(id: @tenant_ids).order(:name).pluck(:name, :id)
      @several_tenants = @tenants.size > 1
      scope = scope.where(tenant_id: params[:tenant]) if params[:tenant].present?
      @promises = scope.includes(:customer, :contract, :user, :tenant, promise_bills: :bill).order(:promised_on, :id).to_a
      @cable = Current.user.tenant_ids_with("record_contact_attempts").map { |id| { channel: "PromisesChannel", tenant_id: id } }.to_json
      render partial: "promises/pendings/result" if htmx_fragment?
    end
  end
end
