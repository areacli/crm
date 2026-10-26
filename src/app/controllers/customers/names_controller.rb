module Customers
  # Corrige o nome do cliente na ficha (06, R113); o documento não se edita (R115). Fica "mantido pelo credor". O formulário abre no painel lateral.
  class NamesController < ApplicationController
    before_action :set_customer

    def edit
      authorize @customer, :edit_registry?
    end

    def update
      authorize @customer, :edit_registry?
      Registry::ContactEditor.new(Current.user).rename(@customer, params.expect(customer: [ :name ])[:name])
      panel_finish(customer_path(@customer), notice: t(".done"), atualizar: true)
    rescue Registry::Refused => error
      @error = error.message
      return redirect_to(customer_path(@customer), alert: error.message, status: :see_other) unless panel_request?

      render :edit, status: :unprocessable_content
    end

    private
      def set_customer = @customer = Customer.find(params[:customer_id])
  end
end
