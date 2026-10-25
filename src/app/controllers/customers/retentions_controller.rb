module Customers
  # Retenção do cliente (07, R138): reter e desfazer, os dois com motivo. Volta para a página de onde veio (a de guarda).
  class RetentionsController < ApplicationController
    before_action :set_customer

    def create
      Titular::Retainer.new(Current.user).retain(@customer, reason)
      redirect_back_or_to data_retention_path, notice: t(".done"), status: :see_other
    end

    def destroy
      Titular::Retainer.new(Current.user).release(@customer, reason)
      redirect_back_or_to data_retention_path, notice: t(".done"), status: :see_other
    end

    private
      def set_customer
        @customer = Customer.includes(:tenant).find(params[:customer_id])
        authorize @customer, :handle_rights?
      end

      def reason = params.expect(retention: [ :reason ])[:reason]
  end
end
