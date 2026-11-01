# Distribuição (14, R311, R312, R317, R326): o que está com qual operação desde quando, distribuir à mão, mudar a exposição e o fim.
class DistributionsController < ApplicationController
  before_action :set_distribution, only: %i[edit update]

  def index
    authorize Distribution
    @tenants = manageable_tenants
    @several_tenants = @tenants.size > 1
    @operations = Operation.joins(:accreditations).where(accreditations: { tenant_id: @tenants.map(&:id) }).distinct.order(:short_name)
    scope = policy_scope(Distribution).includes(:operation, :customer, :contract, :created_by, :tenant).order(created_at: :desc)
    scope = scope.where(tenant_id: params[:tenant]) if params[:tenant].present?
    scope = scope.where(operation_id: params[:operation]) if params[:operation].present?
    scope = scope.where(source: params[:source]) if params[:source].present?
    scope = case params[:status]
    when "in_force" then scope.in_force
    when "scheduled" then scope.open.where("starts_on > ?", Date.current)
    when "ended" then scope.where.not(ended_at: nil)
    else scope
    end
    if params[:q].present?
      term = "%#{Customer.sanitize_sql_like(params[:q].strip)}%"
      scope = scope.left_joins(:customer, :contract).where("customers.name ILIKE :t OR customers.document = :d OR contracts.code ILIKE :t", t: term, d: Document.normalize(params[:q]))
    end
    @pagination = Pagination.new(scope, page: params[:page], per_page: params[:per_page])
    @distributions = @pagination.records
    render partial: "distributions/result" if htmx_fragment?
  end

  def new
    authorize Distribution
    @tenants = manageable_tenants
    @accreditations = active_accreditations
  end

  def create
    @tenants = manageable_tenants
    @accreditations = active_accreditations
    attributes = params.expect(distribution: %i[accreditation_id target value exposure starts_on ends_on])
    accreditation = @accreditations.find { |item| item.id == attributes[:accreditation_id].to_i } or return refuse(t("distributions.refused.target_required"))
    authorize Distribution.new(tenant: accreditation.tenant)
    target = find_target(accreditation.tenant, attributes[:target], attributes[:value])
    distribution = Distributions::Distributor.new(Current.user).distribute(
      tenant: accreditation.tenant, operation: accreditation.operation, **target, exposure: attributes[:exposure].presence,
      starts_on: date(attributes[:starts_on]) || Date.current, ends_on: date(attributes[:ends_on])
    )
    panel_finish(distributions_path, notice: t(".done", target: distribution.target_label, name: accreditation.operation.short_name), atualizar: true)
  rescue Distributions::Refused, ActiveRecord::RecordInvalid => error
    refuse(error.respond_to?(:record) ? error.record.errors.full_messages.to_sentence : error.message)
  end

  def edit
  end

  def update
    attributes = params.expect(distribution: %i[exposure starts_on ends_on])
    Distributions::Distributor.new(Current.user).change(@distribution, exposure: attributes[:exposure], ends_on: date(attributes[:ends_on]),
                                                                       starts_on: date(attributes[:starts_on]) || @distribution.starts_on)
    panel_finish(distributions_path, notice: t(".done", target: @distribution.target_label), atualizar: true)
  rescue Distributions::Refused, ActiveRecord::RecordInvalid => error
    @error = error.respond_to?(:record) ? error.record.errors.full_messages.to_sentence : error.message
    render :edit, status: :unprocessable_content
  end

  private
    def set_distribution
      @distribution = policy_scope(Distribution).includes(:operation, :customer, :contract).find(params[:id])
      authorize @distribution, :update?
    end

    def manageable_tenants = Tenant.where(id: Current.user.tenant_ids_with("distribute_portfolio")).order(:name)

    def active_accreditations = Accreditation.active.where(tenant_id: @tenants.map(&:id)).includes(:operation, :tenant).sort_by { |item| [ item.tenant.name, item.operation.short_name ] }

    # Cliente pelo documento ou contrato pelo código, no credor (R311): "cliente ou contrato é só a forma de escolher".
    def find_target(tenant, kind, value)
      raise Distributions::Refused, t("distributions.refused.target_required") if value.blank?

      if kind == "contract"
        contract = Contract.find_by(tenant: tenant, code: value.strip) or raise Distributions::Refused, t("distributions.refused.not_found", value: value)
        { contract: contract }
      else
        customer = Customer.find_by(tenant: tenant, document: Document.normalize(value)) or raise Distributions::Refused, t("distributions.refused.not_found", value: value)
        { customer: customer }
      end
    end

    def date(value) = value.present? ? Date.iso8601(value) : nil

    def refuse(message)
      @error = message
      render :new, status: :unprocessable_content
    end
end
