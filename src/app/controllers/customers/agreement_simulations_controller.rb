module Customers
  # Simulação do acordo na ficha (11, R211 a R216): quem tem "negociar acordos" no credor do cliente escolhe os títulos e os termos e vê a base, os descontos, a
  # entrada e a tabela de parcelas antes de gravar. O formulário se refaz pelo htmx a cada mudança; nada é gravado aqui.
  class AgreementSimulationsController < ApplicationController
    before_action :set_customer

    def new
      @bills = open_bills
      @form = {}
      @held = held_by_bill
    end

    def create
      @form = params.fetch(:agreement, {}).permit(:mode, :down_payment, :down_payment_on, :installments, :day, :replace, :credit, bill_ids: [], discounts: Agreements::Caps::COMPONENTS).to_h.with_indifferent_access
      @bills = open_bills
      @held = held_by_bill
      begin
        input = Agreements::FormParams.input(@form)
        @quote = Agreements::Simulation.new(user: Current.user, customer: @customer, input: input).call
      rescue Agreements::Refused => error
        @problem = error.message
        @field = error.field
      end
      return render(partial: "customers/agreement_simulations/result") if htmx_fragment?

      render :new
    end

    private
      def set_customer
        @customer = Customer.includes(:tenant).find(params[:customer_id])
        authorize Agreement.new(tenant: @customer.tenant, customer: @customer), :create?
        raise ActionController::RoutingError, "Not Found" if @customer.anonymized?
      end

      # Os títulos em cobrança: os comuns, os de estorno e os de acordo (R250); o que o acordo de origem não deixa renegociar aparece desabilitado, com o motivo.
      def open_bills
        bills = Bill.where(customer: @customer).active.where("amount_cents > paid_cents").includes(:contract, :agreement).order(:due_date, :id).to_a
        @ineligible = bills.to_h { |bill| [ bill.id, Agreements::Eligibility.reason(bill, @customer.tenant.setting) ] }.compact
        bills
      end

      # Título preso a uma proposta ou acordo: o operador vê qual e, se for proposta, pode pedir para substituí-la (R218).
      def held_by_bill
        AgreementBill.where(bill_id: @bills.map(&:id), held: true).includes(:agreement).to_h { |row| [ row.bill_id, row.agreement ] }
      end
  end
end
