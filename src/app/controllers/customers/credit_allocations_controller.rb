module Customers
  # Alocar o crédito aguardando alocação do contrato num título do mesmo contrato (11, R239, A6): "administrar acordos" (17) no credor.
  class CreditAllocationsController < ApplicationController
    def create
      customer = Customer.find(params[:customer_id])
      authorize customer, :show?
      raw = params.expect(credit_allocation: %i[contract_id bill_id amount])
      contract = customer.contracts.find(raw[:contract_id])
      authorize contract, :create?, policy_class: CreditTransferPolicy
      bill = Bill.where(contract_id: contract.id).find(raw[:bill_id])
      cents, problem = Money.parse_cents(raw[:amount])
      raise Agreements::Refused, problem.to_s.capitalize unless cents

      outcome = Agreements::Reversion.new(Current.user).allocate_credit!(contract, bill, cents)
      redirect_to customer_path(customer, anchor: "credito"), notice: t(".done", amount: Money.format(outcome.applied), number: bill.number), status: :see_other
    rescue Agreements::Refused => error
      redirect_to customer_path(customer, anchor: "credito"), alert: error.message, status: :see_other
    end
  end
end
