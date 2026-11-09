# Métodos de recebimento do credor (16, R373; antes "canais de recebimento", R45): lista, cadastro, edição e exclusão. A permissão 4 vale no
# credor do método; a lista abre também para quem só tem a 14, que vê as integrações no detalhe de cada método. Quem tem acesso a mais de um
# credor vê os métodos de todos, com a coluna Credor.
module Settings
  class ChannelsController < ApplicationController
    before_action :set_channel, only: %i[edit update destroy]

    def index
      authorize PaymentChannel
      @editable_tenant_ids = Current.user.tenant_ids_with("change_settings")
      @financial_tenant_ids = Current.user.tenant_ids_with("change_financial_policies")
      @tenants = Tenant.where(id: @editable_tenant_ids + @financial_tenant_ids).order(:name).pluck(:name, :id)
      @several_tenants = @tenants.size > 1
      scope = policy_scope(PaymentChannel).includes(:tenant, :payment_accounts).order(:code)
      scope = scope.where(tenant_id: params[:credor]) if params[:credor].present?
      if params[:busca].present?
        term = "%#{PaymentChannel.sanitize_sql_like(params[:busca].strip)}%"
        scope = scope.where("code ILIKE :term OR description ILIKE :term", term: term)
      end
      @pagination = Pagination.new(scope, page: params[:pagina], per_page: params[:por_pagina])
      @channels = @pagination.records
      render partial: "settings/channels/result" if fragment?
    end

    def new
      authorize PaymentChannel
      @tenants = manageable_tenants
      @channel = PaymentChannel.new
    end

    def create
      @tenants = manageable_tenants
      attributes = params.expect(payment_channel: %i[tenant_id kind code description])
      tenant = @tenants.find_by(id: attributes[:tenant_id]) or return head(:not_found)
      authorize PaymentChannel.new(tenant: tenant)
      @channel = manager.create(tenant: tenant, kind: attributes[:kind], code: attributes[:code], description: attributes[:description])
      panel_finish(settings_channels_path, notice: t(".done", code: @channel.code), atualizar: true)
    rescue ActiveRecord::RecordInvalid => error
      @channel = error.record
      render :new, status: :unprocessable_content
    end

    def edit
      @secret = flash[:webhook_secret]
      response.headers["Cache-Control"] = "no-store" if @secret
    end

    def update
      attributes = params.expect(payment_channel: %i[kind code description active])
      manager.update(@channel, kind: attributes[:kind], code: attributes[:code], description: attributes[:description], active: attributes[:active] == "1")
      # Como antes, salvar volta à lista; na SPA, a aba do método passa a ser a da lista (ou dá lugar a ela, se já estiver aberta).
      panel_finish(settings_channels_path, notice: t(".done", code: @channel.code), atualizar: true, navegar: spa?, mesma_aba: true)
    rescue ActiveRecord::RecordInvalid => error
      @channel = error.record
      render :edit, status: :unprocessable_content
    end

    def destroy
      code = @channel.code
      manager.destroy(@channel)
      panel_finish(settings_channels_path, notice: t(".done", code: code), navegar: true, mesma_aba: true)
    end

    private
      def set_channel
        @channel = PaymentChannel.includes(:tenant).find(params[:id])
        authorize @channel
      end

      def manageable_tenants = Tenant.where(id: Current.user.tenant_ids_with("change_settings")).order(:name)

      def manager = Payments::ChannelManager.new(Current.user)
  end
end
