module Customers
  # "Usar crédito" num título de acordo ou de estorno, pela ficha (11, R232b, AI2): quem tem "negociar acordos" (16) no credor. O crédito é o disponível do contrato do título.
  class CreditUsesController < ApplicationController
    def create
      customer = Customer.find(params[:customer_id])
      authorize customer, :show?
      raw = params.expect(credit_use: %i[bill_id amount])
      bill = Bill.where(customer_id: customer.id).find(raw[:bill_id])
      authorize Agreement.new(tenant: customer.tenant), :create?, policy_class: AgreementPolicy
      cents, problem = Money.parse_cents(raw[:amount])
      raise Agreements::Refused, problem.to_s.capitalize unless cents

      outcome = Agreements::CreditOnBill.use!(bill, cents, Current.user)
      redirect_to customer_path(customer, anchor: "titulos"), notice: t(".done", amount: Money.format(outcome.applied), number: bill.number), status: :see_other
    rescue Agreements::Refused => error
      redirect_to customer_path(customer, anchor: "titulos"), alert: error.message, status: :see_other
    end
  end
end
