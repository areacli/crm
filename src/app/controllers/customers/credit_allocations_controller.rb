module Customers
  # Alocar o crédito aguardando alocação do contrato num título do mesmo contrato (11, R239, A6): "administrar acordos" (17) no credor. Abre num modal pequeno.
  class CreditAllocationsController < ApplicationController
    before_action :set_customer

    def new
      authorize @customer, :show?
      @contract = @customer.contracts.find(params[:contract_id])
      authorize @contract, :create?, policy_class: CreditTransferPolicy
      load_bills
    end

    def create
      authorize @customer, :show?
      raw = params.expect(credit_allocation: %i[contract_id bill_id amount])
      @contract = @customer.contracts.find(raw[:contract_id])
      authorize @contract, :create?, policy_class: CreditTransferPolicy
      bill = Bill.where(contract_id: @contract.id).find(raw[:bill_id])
      cents, problem = Money.parse_cents(raw[:amount])
      raise Agreements::Refused, problem.to_s.capitalize unless cents

      outcome = Agreements::Reversion.new(Current.user).allocate_credit!(@contract, bill, cents)
      panel_finish(customer_path(@customer, aba: "pagamentos"), notice: t(".done", amount: Money.format(outcome.applied), number: bill.number), atualizar: true)
    rescue Agreements::Refused => error
      return redirect_to(customer_path(@customer, aba: "pagamentos"), alert: error.message, status: :see_other) unless panel_request?

      @error = error.message
      load_bills
      render :new, status: :unprocessable_content
    end

    private
      def set_customer = @customer = Customer.find(params[:customer_id])

      def load_bills = @bills = Bill.where(contract_id: @contract.id, status: %w[active scheduled]).order(:due_date)
  end
end
