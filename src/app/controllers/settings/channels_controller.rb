# Canais de recebimento do credor (R45): lista, cadastro, edição e exclusão. A permissão 4 vale no credor do canal; quem a tem em mais de
# um credor vê os canais de todos, com a coluna Credor.
module Settings
  class ChannelsController < ApplicationController
    before_action :set_channel, only: %i[edit update destroy]

    def index
      authorize PaymentChannel
      @tenants = manageable_tenants.pluck(:name, :id)
      @several_tenants = @tenants.size > 1
      scope = policy_scope(PaymentChannel).includes(:tenant).order(:code)
      scope = scope.where(tenant_id: params[:tenant]) if params[:tenant].present?
      if params[:q].present?
        term = "%#{PaymentChannel.sanitize_sql_like(params[:q].strip)}%"
        scope = scope.where("code ILIKE :term OR description ILIKE :term", term: term)
      end
      @pagination = Pagination.new(scope, page: params[:page], per_page: params[:per_page])
      @channels = @pagination.records
      render partial: "settings/channels/result" if htmx_fragment?
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
      redirect_to settings_channels_path, notice: t(".done", code: @channel.code), status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      @channel = error.record
      render :edit, status: :unprocessable_content
    end

    def destroy
      code = @channel.code
      manager.destroy(@channel)
      panel_finish(settings_channels_path, notice: t(".done", code: code), navegar: true)
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
