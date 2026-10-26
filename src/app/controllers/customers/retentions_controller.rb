module Customers
  # Retenção do cliente (07, R138): reter e desfazer, os dois com motivo, pedido num modal pequeno (`new` com `desfazer=1` pede o motivo de desfazer).
  class RetentionsController < ApplicationController
    before_action :set_customer

    def new
      @release = params[:desfazer].present?
    end

    def create
      Titular::Retainer.new(Current.user).retain(@customer, reason)
      panel_finish(data_retention_path, notice: t(".done"), atualizar: true)
    rescue Titular::Refused => error
      @release = false
      panel_error(error.message, data_retention_path)
    end

    def destroy
      Titular::Retainer.new(Current.user).release(@customer, reason)
      panel_finish(data_retention_path, notice: t(".done"), atualizar: true)
    rescue Titular::Refused => error
      @release = true
      panel_error(error.message, data_retention_path)
    end

    private
      def set_customer
        @customer = Customer.includes(:tenant).find(params[:customer_id])
        authorize @customer, :handle_rights?
      end

      def reason = params.expect(retention: [ :reason ])[:reason]
  end
end
