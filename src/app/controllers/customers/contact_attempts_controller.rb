module Customers
  # Acionamentos de um cliente, na ficha dele (04): o histórico (R74), o formulário que reage ao resultado e ao contrato (R73, R69c) e o
  # registro (R69 a R73). A permissão 7 (e a 1) vale no credor do cliente (R76); sem ela a recusa vira 404 registrado (R33).
  # O formulário e o histórico são trechos do htmx; sem JavaScript, o registro volta para a ficha.
  class ContactAttemptsController < ApplicationController
    before_action :set_customer

    # Trecho do histórico, refeito na paginação e a cada evento do WebSocket.
    def index
      authorize @customer, :show?
      return redirect_to(customer_path(@customer, page: params[:page], anchor: "acionamentos")) unless htmx_fragment?

      @history = ContactAttempt.history_for(@customer, page: params[:page])
      render partial: "customers/contact_attempts/history", locals: { customer: @customer, history: @history }
    end

    # Campos que dependem da escolha (retorno, aviso do responsável financeiro): dois trechos trocados fora de banda.
    def new
      authorize ContactAttempt.new(tenant: @customer.tenant), :create?
      return redirect_to(customer_path(@customer, anchor: "acionamentos")) unless htmx_fragment?

      form = Contacts::Form.new(@customer, params.fetch(:contact_attempt, {}).permit(*Contacts::Form::PERMITTED))
      render partial: "customers/contact_attempts/dependents", locals: { form: form }
    end

    def create
      authorize ContactAttempt.new(tenant: @customer.tenant), :create?
      values = params.expect(contact_attempt: Contacts::Form::PERMITTED).to_h
      # R122 e PD5: "salvar este contato no cadastro" só vale com a permissão 12 no credor do cliente; sem ela a marca é ignorada.
      save_contact = values[:save_contact].to_s == "1" && policy(@customer).edit_registry?
      warning = Contacts::Recorder.contact_warning(@customer, values[:channel], values[:contact_used])
      Contacts::Recorder.new(Current.user).record(@customer, values, save_contact: save_contact)
      return redirect_to(customer_path(@customer, anchor: "acionamentos"), notice: [ t(".done"), warning ].compact.join(" "), status: :see_other) unless htmx_fragment?

      render_form(Contacts::Form.new(@customer), notice: t(".done"), history: true, warning: warning)
    rescue Contacts::Refused => error
      return redirect_to(customer_path(@customer, anchor: "acionamentos"), alert: error.message, status: :see_other) unless htmx_fragment?

      render_form(Contacts::Form.new(@customer, values, error: error.message), status: :unprocessable_content)
    end

    private
      def set_customer = @customer = Customer.includes(:tenant).find(params[:customer_id])

      def render_form(form, status: :ok, notice: nil, history: false, warning: nil)
        @history = ContactAttempt.history_for(@customer, page: 1) if history
        render partial: "customers/contact_attempts/form_and_history", locals: { form: form, customer: @customer, history: @history, notice: notice, warning: warning }, status: status
      end
  end
end
