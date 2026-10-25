# Lista de divergências de valor (R99): as abertas por padrão, dos credores em que a pessoa confirma pagamentos (permissão 6, MT-4 a MT-6),
# com a coluna Credor e o filtro opcional de credor. O detalhe é a tela onde se trata, com nota.
class ValueDiscrepanciesController < ApplicationController
  STATUSES = %w[open handled].freeze

  def index
    authorize ValueDiscrepancy
    @tenant_ids = Current.user.tenant_ids_with("confirm_payments")
    @several_tenants = @tenant_ids.size > 1
    @status = STATUSES.include?(params[:status]) ? params[:status] : (params[:status] == "all" ? nil : "open")
    scope = policy_scope(ValueDiscrepancy).includes(:bill, :tenant)
    scope = scope.where(status: @status) if @status
    scope = scope.where(tenant_id: params[:tenant]) if params[:tenant].present?
    @pagination = Pagination.new(scope.includes(bill: :customer).recent, page: params[:page], per_page: params[:per_page])
    @discrepancies = @pagination.records
    @tenants = Tenant.where(id: @tenant_ids).order(:name).pluck(:name, :id)
    @view_customer_tenants = Current.user.tenant_ids_with("view_portfolio")
    render partial: "value_discrepancies/result" if htmx_fragment?
  end

  def show
    @discrepancy = ValueDiscrepancy.includes(:tenant, :handled_by, bill: %i[customer contract]).find(params[:id])
    authorize @discrepancy
    @can_view_customer = Current.user.permitted?("view_portfolio", @discrepancy.tenant_id)
  end
end
