module Customers
  # Transferência de crédito entre contratos do mesmo credor, pela ficha do cliente (R55a, permissão 17). Os dois contratos são do mesmo
  # credor; o de origem é um dos contratos do cliente da ficha, e o de destino é achado pelo código, dentro do credor.
  class CreditTransfersController < ApplicationController
    def create
      customer = Customer.find(params[:customer_id])
      authorize customer, :show?
      attributes = params.expect(credit_transfer: %i[from_contract_id to_code amount reason])
      from = customer.contracts.find_by(id: attributes[:from_contract_id]) or return head(:not_found)
      authorize from, :create?, policy_class: CreditTransferPolicy

      cents, problem = Money.parse_cents(attributes[:amount])
      raise Access::Refused, problem.to_s.capitalize unless cents

      to = Contract.find_by(tenant_id: from.tenant_id, code: attributes[:to_code].to_s.strip)
      raise Access::Refused, t(".destination_not_found") unless to

      Payments::CreditTransfer.new(Current.user).transfer(from: from, to: to, cents: cents, reason: attributes[:reason])
      redirect_to customer_path(customer, anchor: "credito"), notice: t(".done", amount: Money.format(cents), to: to.label), status: :see_other
    rescue Access::Refused => error
      redirect_to customer_path(customer, anchor: "credito"), alert: error.message, status: :see_other
    end
  end
end
