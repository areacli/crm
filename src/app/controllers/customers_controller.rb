# Lista de clientes (R21) e ficha (R22). A busca se refaz pelo htmx, sem recarregar a página.
class CustomersController < ApplicationController
  def index
    authorize Customer
    query = Portfolio::Query.new(Current.user)
    bracket = params[:bracket].presence&.to_i
    @pagination = Pagination.new(query.customers(search: params[:q], bracket: bracket, segment: params[:segment], tenant_id: params[:tenant], sort: params[:sort], direction: params[:dir], promise: params[:promise], unrecognized_city: params[:unrecognized_city]),
                                 page: params[:page], per_page: params[:per_page])
    @customers = @pagination.records.includes(:tenant)
    @query = query
    @segment_names = query.segment_names(@customers.map(&:id))
    @updated_totals = query.updated_totals(@customers.map(&:id))
    @settings = query.settings_by_tenant
    @several_tenants = @settings.size > 1
    @tenants = Tenant.where(id: @settings.keys).order(:name).pluck(:name, :id)
    @brackets = bracket_options(@settings)
    @segments = query.segment_options.map { |segment| [ @several_tenants ? "#{segment.name} (#{segment.tenant.name})" : segment.name, segment.id ] } + [ [ t("segments.none"), "none" ] ]
    render partial: "customers/result" if htmx_fragment?
  end

  def show
    @customer = Customer.includes(:tenant).find(params[:id])
    authorize @customer
    @setting = @customer.tenant.setting
    @brackets = Portfolio::AgingBrackets.from_stored(@setting.aging_brackets)
    @bills = Bill.where(customer: @customer).includes(:contract, :agreement).order(:due_date)
    # Aviso do valor mudado (R100): título com mais de uma versão ou com divergência aberta leva ao histórico.
    @version_counts = BillValueVersion.where(bill_id: @bills.map(&:id)).group(:bill_id).count
    @open_discrepancies = ValueDiscrepancy.where(bill_id: @bills.map(&:id), status: "open").distinct.pluck(:bill_id)
    @today = Date.current
    load_payments_and_credits
    load_valuations
    load_segments
    load_contact_attempts
    load_promises
    load_agreements
    load_registry
    load_rights
  end

  private
    # Valor atualizado dos títulos vencidos (09, R174): o último recálculo gravado, com a data dele. Consulta: chave de `bill_valuations`.
    def load_valuations
      @valuations = BillValuation.where(bill_id: @bills.map(&:id)).index_by(&:bill_id)
      @value_status = Charges::Recalculation.status(@customer.tenant)
    end

    # Promessas (10, R203): as abertas e pendentes dos contratos do cliente vão ao cabeçalho; cada título mostra a promessa que o prende. Consultas:
    # `payment_promises (contract_id)` e o índice único parcial dos títulos presos.
    def load_promises
      @promises = Customers::PromisesController.holding_for(@customer)
      @held_bills = PaymentPromiseBill.where(bill_id: @bills.map(&:id), held: true).includes(:promise).index_by(&:bill_id)
    end

    # Acordos (11, R241): as propostas e os acordos em andamento vão ao cabeçalho, o histórico fica abaixo, e o título preso mostra a proposta ou o acordo. A cidade que não
    # casou com o IBGE avisa quem edita o cadastro (AB9). Consultas: `agreements (customer_id)` e o índice parcial dos títulos presos.
    def load_agreements
      @can_negotiate = AgreementPolicy.new(Current.user, Agreement.new(tenant: @customer.tenant)).create? && !@customer.anonymized?
      @can_use_credit = @can_negotiate
      @can_allocate = CreditTransferPolicy.new(Current.user, @customer).create? && @credit_awaiting.values.any?(&:positive?)
      return unless AgreementPolicy.new(Current.user, Agreement.new(tenant: @customer.tenant)).show?

      @agreements = Customers::AgreementsController.running_for(@customer)
      @held_by_agreement = AgreementBill.where(bill_id: @bills.map(&:id), held: true).includes(:agreement).to_h { |row| [ row.bill_id, row.agreement ] }
      @renegotiated_by = AgreementBill.joins(:agreement).where(bill_id: @bills.select(&:renegotiated?).map(&:id), agreements: { state: %w[active_on_time active_late broken settled renegotiated] })
                                      .includes(:agreement).to_h { |row| [ row.bill_id, row.agreement ] }
      @agreement_events = AgreementEvent.joins(:agreement).where(agreements: { customer_id: @customer.id }).includes(:agreement, :user).order(occurred_at: :desc, id: :desc).limit(30).to_a
      @city_unrecognized = policy(@customer).edit_registry? && Agreements::Square.unrecognized?(@customer)
    end

    # Direitos do titular (07, R141): os botões da ficha só para quem tem a 13 (e a 1) no credor, e o que impede anonimizar, dito antes (R130).
    def load_rights
      @can_handle_rights = policy(@customer).handle_rights?
      @open_relations = Titular::OpenRelations.new(@customer) if @can_handle_rights && !@customer.anonymized?
    end

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
      @contact_form = Contacts::Form.new(@customer) if !@customer.anonymized? && policy(ContactAttempt.new(tenant: @customer.tenant)).create?
    end

    # Segmento de cada contrato (R159): ao lado da faixa de atraso do contrato, com o histórico de mudanças. Consultas: `bills (contract_id)` e
    # `contract_segments (contract_id, since)`.
    def load_segments
      ids = @contracts.map(&:id)
      @contract_overdue = Bill.overdue(@today).where(contract_id: ids).group(:contract_id).minimum(:due_date).transform_values { |due| (@today - due).to_i }
      @contract_segments = Segment.where(id: @contracts.filter_map(&:segment_id)).index_by(&:id)
      @segment_history = ContractSegment.where(contract_id: ids).includes(:segment).order(since: :desc, id: :desc).limit(100).group_by(&:contract_id)
    end

    # Pagos (R54) e crédito por contrato (R55b): o crédito é do contrato, visível a todos os clientes dele, sem total por cliente.
    def load_payments_and_credits
      # Pagamentos de promessa não têm título (10, R194): aparecem pelo número da promessa, nas promessas dos contratos do cliente.
      promise_ids = PaymentPromise.where(contract_id: ContractCustomer.where(customer_id: @customer.id).select(:contract_id)).select(:id)
      @payments = Payment.where(bill_id: @bills.map(&:id)).or(Payment.where(promise_id: promise_ids)).applied.includes(:channel, :bill).order(paid_on: :desc, id: :desc)
      @contracts = @customer.contracts.order(:code, :id).to_a
      # O crédito por estado (11, R233, R239): o disponível, o que aguarda alocação (reversão) e o bloqueado (estorno à espera do gestor).
      by_bucket = Credit.where(contract_id: @contracts.map(&:id)).group(:contract_id, :bucket).sum(:amount_cents)
      @credit_totals = by_bucket.select { |(_, bucket), _| bucket == "available" }.to_h { |(contract_id, _), cents| [ contract_id, cents ] }
      @credit_awaiting = by_bucket.select { |(_, bucket), _| bucket == "awaiting" }.to_h { |(contract_id, _), cents| [ contract_id, cents ] }
      @credit_blocked = by_bucket.select { |(_, bucket), _| bucket == "blocked" }.to_h { |(contract_id, _), cents| [ contract_id, cents ] }
      @credit_entries = Credit.where(contract_id: @contracts.map(&:id)).includes(:payment, :related_contract).recent.limit(100).group_by(&:contract_id)
      @allocatable_bills = Bill.where(contract_id: @contracts.map(&:id), status: %w[active scheduled]).order(:due_date).group_by(&:contract_id) if @credit_awaiting.values.any?(&:positive?)
      # Excedente de título com valor reduzido (05, R90): crédito calculado do contrato, de qualquer título dele. Índice: `bills (contract_id)`.
      @excess_bills = Bill.where(contract_id: @contracts.map(&:id)).where("paid_cents > amount_cents").order(:number).group_by(&:contract_id)
      @excess_totals = @excess_bills.transform_values { |bills| bills.sum(&:excess_cents) }
      @can_transfer = CreditTransferPolicy.new(Current.user, @customer).create? && (@credit_totals.values + @credit_awaiting.values).any?(&:positive?)
    end

    # Opções do filtro de faixa: com um só credor, as faixas dele; com vários, as do primeiro (a lista filtra cada cliente pelas do credor dele).
    def bracket_options(settings)
      brackets = Portfolio::AgingBrackets.from_stored(settings.values.first&.aging_brackets || TenantSetting::DEFAULT_BRACKETS)
      [ [ "Sem atraso", -1 ] ] + brackets.labels.each_with_index.map { |label, index| [ label, index ] }
    end
end
