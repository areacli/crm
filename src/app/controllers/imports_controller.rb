# Importações de carteira, de pagamentos e de estornos (R10, R56): lista, envio do arquivo e acompanhamento. O andamento chega pelo
# WebSocket (`cable:import-changed`), que faz o htmx refazer só o trecho da tela.
class ImportsController < ApplicationController
  def index
    authorize Import
    @pagination = Pagination.new(policy_scope(Import).includes(:tenant, :user).recent, page: params[:page], per_page: params[:per_page])
    @imports = @pagination.records
    render partial: "imports/list" if htmx_fragment?
  end

  def show
    @import = Import.includes(:tenant, :user).find(params[:id])
    authorize @import
    @rejections = @import.rejections.order(:line).limit(50)
    render partial: "imports/state", locals: { import: @import, rejections: @rejections } if htmx_fragment?
  end

  def new
    @kind = kind_param(params[:kind])
    authorize Import.new(kind: @kind), :new?
    @tenants = uploadable_tenants(@kind)
  end

  def create
    @kind = kind_param(params.dig(:import, :kind))
    tenant = uploadable_tenants(@kind).find_by(id: params.expect(import: %i[tenant_id])[:tenant_id])
    return head :not_found unless tenant

    authorize Import.new(tenant: tenant, kind: @kind)
    file = params.dig(:import, :file)
    # Pagamentos e estornos não têm modo: o arquivo só acrescenta (R48).
    mode = @kind == "portfolio" && Import.modes.key?(params.dig(:import, :mode)) ? params.dig(:import, :mode) : "incremental"
    return refuse(tenant, "Escolha o arquivo CSV.") if file.blank?

    import = Portfolio::ImportService.new.start(tenant: tenant, user: Current.user, file: file, mode: mode, kind: @kind)
    redirect_to import, notice: "Arquivo recebido. A conferência começou."
  rescue Portfolio::ImportRefused => error
    refuse(tenant, "#{error.message.capitalize}.")
  end

  private
    def kind_param(value) = Import.kinds.key?(value) ? value : "portfolio"

    def uploadable_tenants(kind) = Tenant.where(id: Current.user.tenant_ids_with(ImportPolicy::UPLOAD.fetch(kind))).order(:name)

    def refuse(tenant, message)
      @tenants = uploadable_tenants(@kind)
      @error = message
      @selected_tenant = tenant&.id
      render :new, status: :unprocessable_content
    end
end
