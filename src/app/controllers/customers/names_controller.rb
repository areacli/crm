module Customers
  # Corrige o nome do cliente na ficha (06, R113); o documento não se edita (R115). Fica "mantido pelo credor".
  class NamesController < ApplicationController
    def update
      customer = Customer.find(params[:customer_id])
      authorize customer, :edit_registry?
      Registry::ContactEditor.new(Current.user).rename(customer, params.expect(customer: [ :name ])[:name])
      redirect_to customer_path(customer), notice: t(".done"), status: :see_other
    rescue Registry::Refused => error
      redirect_to customer_path(customer), alert: error.message, status: :see_other
    end
  end
end
