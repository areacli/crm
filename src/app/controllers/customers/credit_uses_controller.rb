module Customers
  # "Usar crédito" num título de acordo ou de estorno, pela ficha (11, R232b, AI2): quem tem "negociar acordos" (16) no credor. O crédito é o disponível do contrato do título.
  # O valor se pede num modal pequeno.
  class CreditUsesController < ApplicationController
    before_action :set_customer

    def new
      authorize @customer, :show?
      authorize Agreement.new(tenant: @customer.tenant), :create?, policy_class: AgreementPolicy
      @bill = Bill.where(customer_id: @customer.id).find(params[:bill_id])
    end

    def create
      authorize @customer, :show?
      raw = params.expect(credit_use: %i[bill_id amount])
      @bill = Bill.where(customer_id: @customer.id).find(raw[:bill_id])
      authorize Agreement.new(tenant: @customer.tenant), :create?, policy_class: AgreementPolicy
      cents, problem = Money.parse_cents(raw[:amount])
      raise Agreements::Refused, problem.to_s.capitalize unless cents

      outcome = Agreements::CreditOnBill.use!(@bill, cents, Current.user)
      panel_finish(customer_path(@customer, aba: "titulos"), notice: t(".done", amount: Money.format(outcome.applied), number: @bill.number), atualizar: true)
    rescue Agreements::Refused => error
      return redirect_to(customer_path(@customer, aba: "titulos"), alert: error.message, status: :see_other) unless panel_request?

      @error = error.message
      render :new, status: :unprocessable_content
    end

    private
      def set_customer = @customer = Customer.find(params[:customer_id])
  end
end
