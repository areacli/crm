# Lista de clientes (R21) e ficha (R22). A busca se refaz pelo htmx, sem recarregar a página.
class CustomersController < ApplicationController
  def index
    authorize Customer
    query = Portfolio::Query.new(Current.user)
    bracket = params[:bracket].presence&.to_i
    @pagination = Pagination.new(query.customers(search: params[:q], bracket: bracket, tenant_id: params[:tenant], sort: params[:sort], direction: params[:dir]),
                                 page: params[:page], per_page: params[:per_page])
    @customers = @pagination.records.includes(:tenant)
    @query = query
    @settings = query.settings_by_tenant
    @several_tenants = @settings.size > 1
    @tenants = Tenant.where(id: @settings.keys).order(:name).pluck(:name, :id)
    @brackets = bracket_options(@settings)
    render partial: "customers/result" if htmx_fragment?
  end

  def show
    @customer = Customer.includes(:tenant).find(params[:id])
    authorize @customer
    @setting = @customer.tenant.setting
    @brackets = Portfolio::AgingBrackets.from_stored(@setting.aging_brackets)
    @bills = Bill.where(customer: @customer).includes(:contract).order(:due_date)
    # Aviso do valor mudado (R100): título com mais de uma versão ou com divergência aberta leva ao histórico.
    @version_counts = BillValueVersion.where(bill_id: @bills.map(&:id)).group(:bill_id).count
    @open_discrepancies = ValueDiscrepancy.where(bill_id: @bills.map(&:id), status: "open").distinct.pluck(:bill_id)
    @today = Date.current
    load_payments_and_credits
    load_contact_attempts
    load_registry
  end

  private
    # Cadastro (06): contatos do cliente (R124), o histórico do cadastro (R116) e os contratos com os papéis, só para leitura (R124a). Consulta dos
    # contatos: `customer_contacts (customer_id, kind, key)`; do histórico: `changes (subject_type, subject_id)`.
    def load_registry
      @contacts = @customer.contacts.includes(:updated_by).to_a
      @top_contacts = CustomerContact.top_valid(@customer, @contacts)
      @listed_contacts = CustomerContact.listed(@contacts)
      @can_edit_registry = policy(@customer).edit_registry?
      @registry_history = Change.where("(subject_type = 'customer' and subject_id = ? and field = 'name') or (subject_type = 'customer_contact' and subject_id in (?))",
                                       @customer.id, @contacts.map(&:id).presence || [ 0 ]).includes(:user).order(occurred_at: :desc, id: :desc).limit(50).to_a
      @contract_members = ContractCustomer.where(contract_id: @contracts.map(&:id)).includes(:customer).group_by(&:contract_id)
    end

    # Acionamentos (04): o histórico de 20 em 20 (R74) e o formulário, só para quem registra no credor do cliente (R76).
    def load_contact_attempts
      @contact_history = ContactAttempt.history_for(@customer, page: params[:page])
      @contact_form = Contacts::Form.new(@customer) if policy(ContactAttempt.new(tenant: @customer.tenant)).create?
    end

    # Pagos (R54) e crédito por contrato (R55b): o crédito é do contrato, visível a todos os clientes dele, sem total por cliente.
    def load_payments_and_credits
      @payments = Payment.where(bill_id: @bills.map(&:id)).applied.includes(:channel, :bill).order(paid_on: :desc, id: :desc)
      @contracts = @customer.contracts.order(:code, :id).to_a
      @credit_totals = Credit.where(contract_id: @contracts.map(&:id)).group(:contract_id).sum(:amount_cents)
      @credit_entries = Credit.where(contract_id: @contracts.map(&:id)).includes(:payment, :related_contract).recent.limit(100).group_by(&:contract_id)
      # Excedente de título com valor reduzido (05, R90): crédito calculado do contrato, de qualquer título dele. Índice: `bills (contract_id)`.
      @excess_bills = Bill.where(contract_id: @contracts.map(&:id)).where("paid_cents > amount_cents").order(:number).group_by(&:contract_id)
      @excess_totals = @excess_bills.transform_values { |bills| bills.sum(&:excess_cents) }
      @can_transfer = CreditTransferPolicy.new(Current.user, @customer).create? && @credit_totals.values.any?(&:positive?)
    end

    # Opções do filtro de faixa: com um só credor, as faixas dele; com vários, as do primeiro (a lista filtra cada cliente pelas do credor dele).
    def bracket_options(settings)
      brackets = Portfolio::AgingBrackets.from_stored(settings.values.first&.aging_brackets || TenantSetting::DEFAULT_BRACKETS)
      [ [ "Sem atraso", -1 ] ] + brackets.labels.each_with_index.map { |label, index| [ label, index ] }
    end
end
