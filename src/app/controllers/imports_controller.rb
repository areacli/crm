# Importações de carteira (R10): lista, envio do arquivo e acompanhamento. O andamento chega pelo WebSocket (`cable:import-changed`),
# que faz o htmx refazer só o trecho da tela.
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
    authorize Import
    @tenants = uploadable_tenants
  end

  def create
    tenant = uploadable_tenants.find_by(id: params.expect(import: %i[tenant_id])[:tenant_id])
    return head :not_found unless tenant

    authorize Import.new(tenant: tenant)
    file = params.dig(:import, :file)
    mode = Import.modes.key?(params.dig(:import, :mode)) ? params.dig(:import, :mode) : "incremental"
    return refuse(tenant, "Escolha o arquivo CSV da carteira.") if file.blank?

    import = Portfolio::ImportService.new.start(tenant: tenant, user: Current.user, file: file, mode: mode)
    redirect_to import, notice: "Arquivo recebido. A conferência começou."
  rescue Portfolio::ImportRefused => error
    refuse(tenant, "#{error.message.capitalize}.")
  end

  private
    def uploadable_tenants = Tenant.where(id: Current.user.tenant_ids_with("upload_imports")).order(:name)

    def refuse(tenant, message)
      @tenants = uploadable_tenants
      @error = message
      @selected_tenant = tenant&.id
      render :new, status: :unprocessable_content
    end
end
