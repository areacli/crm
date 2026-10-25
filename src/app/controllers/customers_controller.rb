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
    @today = Date.current
  end

  private
    # Opções do filtro de faixa: com um só credor, as faixas dele; com vários, as do primeiro (a lista filtra cada cliente pelas do credor dele).
    def bracket_options(settings)
      brackets = Portfolio::AgingBrackets.from_stored(settings.values.first&.aging_brackets || TenantSetting::DEFAULT_BRACKETS)
      [ [ "Sem atraso", -1 ] ] + brackets.labels.each_with_index.map { |label, index| [ label, index ] }
    end
end
