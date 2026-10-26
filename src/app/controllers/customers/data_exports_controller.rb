module Customers
  # Exportação dos dados do cliente (07, R127 a R129): o pedido leva o motivo, fica registrado (sem o conteúdo) e abre a página com um endereço
  # assinado que vale 10 minutos para quem pediu. A mesma página sai em JSON (portabilidade). A permissão 13 e a 1 valem no credor do cliente.
  class DataExportsController < ApplicationController
    TOKEN_LIFETIME = 10.minutes

    layout :layout_da_exportacao
    before_action :set_customer

    # Pede o motivo, num modal pequeno.
    def new
      authorize @customer, :handle_rights?
    end

    def create
      authorize @customer, :handle_rights?
      reason = params.expect(export: [ :reason ])[:reason].to_s.strip
      raise Titular::Refused, t(".reason_required") if reason.empty?

      Change.record!(tenant_id: @customer.tenant_id, user: Current.user, subject_type: "customer", subject_id: @customer.id, event: "data_exported", note: reason[0, 300], origin: "screen")
      destination = customer_data_export_path(@customer, token: verifier.generate([ @customer.id, Current.user.id ], expires_in: TOKEN_LIFETIME, purpose: :data_export))
      # Pelo painel, o htmx leva o navegador à página para imprimir (a exportação é uma página, não um trecho).
      return head(:no_content, "HX-Redirect": destination) if panel_request?

      redirect_to destination, status: :see_other
    rescue Titular::Refused => error
      raise unless panel_request?

      @error = error.message
      render :new, status: :unprocessable_content
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
      # A página para imprimir tem layout próprio; o pedido do motivo (modal) usa o layout do painel.
      def layout_da_exportacao = action_name == "show" ? "impressao" : layout_da_resposta

      def set_customer = @customer = Customer.includes(:tenant).find(params[:customer_id])

      def verifier = Rails.application.message_verifier(:data_export)
  end
end
