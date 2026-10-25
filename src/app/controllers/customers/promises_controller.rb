module Customers
  # Promessas abertas e pendentes na ficha do cliente (10, R203, P17): as dos contratos em que ele figura, com quem prometeu. Trecho do htmx, refeito a cada
  # evento do WebSocket. Quem pode consultar a carteira no credor do cliente.
  class PromisesController < ApplicationController
    def index
      customer = Customer.includes(:tenant).find(params[:customer_id])
      authorize customer, :show?
      return redirect_to(customer_path(customer, anchor: "promessas")) unless htmx_fragment?

      render partial: "customers/promises/lines", locals: { customer: customer, promises: Customers::PromisesController.holding_for(customer) }
    end

    def self.holding_for(customer)
      PaymentPromise.holding.where(contract_id: ContractCustomer.where(customer_id: customer.id).select(:contract_id)).includes(:customer, :contract, :tenant, promise_bills: :bill).order(:promised_on, :id).to_a
    end
  end
end
