# Importações de carteira, de pagamentos e de estornos (R10, R56): lista, envio do arquivo e acompanhamento. O andamento chega pelo
# WebSocket (`cable:import-changed`), que faz a SPA refazer só o trecho da tela.
class ImportsController < ApplicationController
  def index
    authorize Import
    @pagination = Pagination.new(policy_scope(Import).includes(:tenant, :user, :source_system).recent, page: params[:pagina], per_page: params[:por_pagina])
    @imports = @pagination.records
    # R422: a coluna "Sistema" só existe quando algum credor da pessoa tem mais de um sistema além do CRM.
    @multi_system_tenants = SourceSystem.role_remote.where(tenant_id: import_tenant_ids).distinct.pluck(:tenant_id).to_set
    @with_systems = @multi_system_tenants.any?
    render partial: "imports/list" if fragment?
  end

  def show
    @import = Import.includes(:tenant, :user, :source_system).find(params[:id])
    authorize @import
    @rejections = @import.rejections.order(:line).limit(50)
    render partial: "imports/state", locals: { import: @import, rejections: @rejections } if fragment?
  end

  def new
    @kind = kind_param(FilterValue.from_url(params[:tipo]))
    authorize Import.new(kind: @kind), :new?
    prepare_form
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

    system = chosen_system(tenant)
    return refuse(tenant, "Escolha o sistema.") if system == :missing

    import = start_import(tenant, file, mode, system)
    # Na SPA (decisão 0028), a importação abre na aba dela, onde o andamento chega pelo tempo real.
    return panel_finish(import_path(import), notice: "Arquivo recebido. A conferência começou.", navegar: true) if spa?

    redirect_to import, notice: "Arquivo recebido. A conferência começou."
  rescue Portfolio::ImportRefused => error
    refuse(tenant, "#{error.message.upcase_first}.")
  end

  private
    # Na demonstração o arquivo do visitante é descartado sem ser lido e entra um fictício (LGPD, o documento da demonstração do projeto).
    def start_import(tenant, file, mode, system)
      service = Portfolio::ImportService.new
      return service.start(tenant: tenant, user: Current.user, file: file, mode: mode, kind: @kind, source_system: system) unless Demo.enabled?

      # O tamanho vem do cabeçalho do envio (o conteúdo não é lido); o limite continua valendo na demonstração (V5).
      raise Portfolio::ImportRefused, "arquivo acima do limite de 50 MB" if file.respond_to?(:size) && file.size > Ingestion::CsvReader::MAX_BYTES

      substitute = Demo::Files.for(@kind, tenant, system)
      begin
        service.start(tenant: tenant, user: Current.user, file: substitute, mode: mode, kind: @kind, original_name: Demo::Files::NAME, source_system: system)
      ensure
        FileUtils.rm_f(substitute)
      end
    end

    # Os credores em que a pessoa envia ou confirma alguma importação.
    def import_tenant_ids = (ImportPolicy::UPLOAD.values + ImportPolicy::CONFIRM.values).uniq.flat_map { |permission| Current.user.tenant_ids_with(permission) }.uniq

    def kind_param(value) = Import.kinds.key?(value) ? value : "portfolio"

    def uploadable_tenants(kind) = Tenant.where(id: Current.user.tenant_ids_with(ImportPolicy::UPLOAD.fetch(kind))).order(:name)

    # R400: os sistemas que recebem carteira, por credor, pausados incluídos (aparecem desabilitados). Só a carteira escolhe sistema no envio;
    # os pagamentos trazem o sistema por linha.
    def systems_by_tenant(tenants)
      return {} unless @kind == "portfolio"

      SourceSystem.receiving.where(tenant_id: tenants.map(&:id)).order(:role, :name).group_by(&:tenant_id)
    end

    # O sistema do envio: com um só no credor, é ele (o serviço assume); com mais de um, a pessoa escolhe. `:missing` é a escolha que faltou.
    def chosen_system(tenant)
      return unless @kind == "portfolio"

      systems = SourceSystem.receiving.where(tenant_id: tenant.id)
      return if systems.count < 2

      systems.find_by(id: params.dig(:import, :source_system_id)) || :missing
    end

    # O formulário de envio: os credores da pessoa, os sistemas de cada um e o que a tabela de colunas mostra: os ids remotos na carteira (R401) e as
    # colunas `sistema` e `id_titulo` nos pagamentos e estornos (R416, R417), para quem tem credor com sistema remoto.
    def prepare_form
      @tenants = uploadable_tenants(@kind)
      @systems = systems_by_tenant(@tenants)
      @with_ids = @systems.values.flatten.any?(&:role_remote?)
      @remote = @kind == "portfolio" ? [] : SourceSystem.role_remote.where(tenant_id: @tenants.map(&:id)).to_a
    end

    def refuse(tenant, message)
      prepare_form
      @selected_system = params.dig(:import, :source_system_id)
      @error = message
      @selected_tenant = tenant&.id
      render :new, status: :unprocessable_content
    end
end
