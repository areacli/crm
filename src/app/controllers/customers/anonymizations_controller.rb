module Customers
  # Anonimização a pedido do titular (07, R130 a R135): motivo e documento digitado; recusa com a relação em aberto. A 13 e a 1 no credor. Abre num modal pequeno.
  class AnonymizationsController < ApplicationController
    before_action :set_customer

    def new
      authorize @customer, :handle_rights?
      @open_relations = Titular::OpenRelations.new(@customer)
    end

    def create
      authorize @customer, :handle_rights?
      values = params.expect(anonymization: %i[reason document])
      Titular::Anonymizer.on_request(@customer, actor: Current.user, reason: values[:reason], document: values[:document])
      panel_finish(customer_path(@customer), notice: t(".done"), atualizar: true)
    rescue Titular::Refused => error
      return redirect_to(customer_path(@customer), alert: error.message, status: :see_other) unless panel_request?

      @error = error.message
      @open_relations = Titular::OpenRelations.new(@customer)
      render :new, status: :unprocessable_content
    end

    private
      def set_customer = @customer = Customer.includes(:tenant).find(params[:customer_id])
  end
end
