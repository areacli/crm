module Customers
  # Transferência de crédito entre contratos do mesmo credor, pela ficha do cliente (R55a, permissão 17). Os dois contratos são do mesmo
  # credor; o de origem é um dos contratos do cliente da ficha, e o de destino é achado pelo código, dentro do credor. Abre no painel lateral.
  class CreditTransfersController < ApplicationController
    before_action :set_customer

    def new
      authorize @customer, :show?
      authorize @customer, :create?, policy_class: CreditTransferPolicy
      load_sources
    end

    def create
      authorize @customer, :show?
      attributes = params.expect(credit_transfer: %i[from_contract_id to_code amount reason])
      from = @customer.contracts.find_by(id: attributes[:from_contract_id]) or return head(:not_found)
      authorize from, :create?, policy_class: CreditTransferPolicy

      cents, problem = Money.parse_cents(attributes[:amount])
      raise Access::Refused, problem.to_s.capitalize unless cents

      to = Contract.find_by(tenant_id: from.tenant_id, code: attributes[:to_code].to_s.strip)
      raise Access::Refused, t(".destination_not_found") unless to

      Payments::CreditTransfer.new(Current.user).transfer(from: from, to: to, cents: cents, reason: attributes[:reason])
      panel_finish(customer_path(@customer, aba: "pagamentos"), notice: t(".done", amount: Money.format(cents), to: to.label), atualizar: true)
    rescue Access::Refused => error
      return redirect_to(customer_path(@customer, aba: "pagamentos"), alert: error.message, status: :see_other) unless panel_request?

      @error = error.message
      load_sources
      render :new, status: :unprocessable_content
    end

    private
      def set_customer = @customer = Customer.find(params[:customer_id])

      # Contratos de origem com crédito (disponível ou aguardando alocação) e o valor de cada um.
      def load_sources
        by_bucket = Credit.where(contract_id: @customer.contracts.select(:id)).where(bucket: %w[available awaiting]).group(:contract_id).sum(:amount_cents)
        @sources = @customer.contracts.order(:code, :id).select { |contract| by_bucket.fetch(contract.id, 0).positive? }.map { |contract| [ "#{contract.label} (#{helpers.money(by_bucket[contract.id])})", contract.id ] }
      end
  end
end
