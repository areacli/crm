module Customers
  # Acordos do cliente: o trecho da ficha, refeito a cada evento do WebSocket (index), e a gravação da proposta (create, R211 a R218). Quem tem "negociar
  # acordos" no credor do cliente; o credor é sempre o do cliente (MT-8), sem campo de credor no formulário.
  class AgreementsController < ApplicationController
    def index
      customer = Customer.includes(:tenant).find(params[:customer_id])
      authorize customer, :show?
      return redirect_to(customer_path(customer, anchor: "acordos")) unless htmx_fragment?

      render partial: "customers/agreements/lines", locals: { customer: customer, agreements: Customers::AgreementsController.running_for(customer) }
    end

    def create
      customer = Customer.includes(:tenant).find(params[:customer_id])
      authorize Agreement.new(tenant: customer.tenant, customer: customer), :create?
      raw = params.fetch(:agreement, {}).permit(:mode, :down_payment, :down_payment_on, :installments, :day, :replace, :credit, bill_ids: [], discounts: Agreements::Caps::COMPONENTS).to_h.with_indifferent_access
      agreement = Agreements::Proposal.new(Current.user, customer).create(Agreements::FormParams.input(raw))
      redirect_to agreement_path(agreement), notice: t(".done", number: agreement.number), status: :see_other
    rescue Agreements::Refused => error
      # A recusa volta ao formulário, com o que foi digitado e a mensagem junto do campo.
      @customer = customer
      @form = raw
      @bills = Bill.where(customer: customer).active.kind_common.where("amount_cents > paid_cents").includes(:contract).order(:due_date, :id).to_a
      @held = AgreementBill.where(bill_id: @bills.map(&:id), held: true).includes(:agreement).to_h { |row| [ row.bill_id, row.agreement ] }
      @create_problem = error.message
      @field = error.field
      @problem = error.message
      render "customers/agreement_simulations/new", status: :unprocessable_content
    end

    # Propostas e acordos do cliente que a ficha mostra no cabeçalho: as propostas numa linha só, os acordos aceitos e não terminados um por linha.
    def self.running_for(customer)
      Agreement.where(customer_id: customer.id, state: Agreement::PROPOSAL + Agreement::RUNNING).includes(:tenant, agreement_bills: :bill).order(:created_at, :id).to_a
    end
  end
end
