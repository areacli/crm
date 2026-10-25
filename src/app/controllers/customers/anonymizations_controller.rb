module Customers
  # Anonimização a pedido do titular (07, R130 a R135): motivo e documento digitado; recusa com a relação em aberto. A 13 e a 1 no credor.
  class AnonymizationsController < ApplicationController
    def create
      customer = Customer.includes(:tenant).find(params[:customer_id])
      authorize customer, :handle_rights?
      values = params.expect(anonymization: %i[reason document])
      Titular::Anonymizer.on_request(customer, actor: Current.user, reason: values[:reason], document: values[:document])
      redirect_to customer_path(customer), notice: t(".done"), status: :see_other
    rescue Titular::Refused => error
      redirect_to customer_path(customer), alert: error.message, status: :see_other
    end
  end
end
