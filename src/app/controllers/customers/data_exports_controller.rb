module Customers
  # Exportação dos dados do cliente (07, R127 a R129): o pedido leva o motivo, fica registrado (sem o conteúdo) e abre a página com um endereço
  # assinado que vale 10 minutos para quem pediu. A mesma página sai em JSON (portabilidade). A permissão 13 e a 1 valem no credor do cliente.
  class DataExportsController < ApplicationController
    TOKEN_LIFETIME = 10.minutes

    layout "impressao", only: :show
    before_action :set_customer

    def create
      authorize @customer, :handle_rights?
      reason = params.expect(export: [ :reason ])[:reason].to_s.strip
      raise Titular::Refused, t(".reason_required") if reason.empty?

      Change.record!(tenant_id: @customer.tenant_id, user: Current.user, subject_type: "customer", subject_id: @customer.id, event: "data_exported", note: reason[0, 300], origin: "screen")
      redirect_to customer_data_export_path(@customer, token: verifier.generate([ @customer.id, Current.user.id ], expires_in: TOKEN_LIFETIME, purpose: :data_export)), status: :see_other
    end

    def show
      authorize @customer, :handle_rights?
      customer_id, user_id = verifier.verified(params[:token].to_s, purpose: :data_export)
      return head(:not_found) unless customer_id == @customer.id && user_id == Current.user.id

      @data = Titular::Exporter.new(@customer).to_h
      respond_to do |format|
        format.html
        format.json { send_data JSON.pretty_generate(@data), type: "application/json", disposition: %(attachment; filename="dados-cliente-#{@customer.id}.json") }
      end
    end

    private
      def set_customer = @customer = Customer.includes(:tenant).find(params[:customer_id])

      def verifier = Rails.application.message_verifier(:data_export)
  end
end
