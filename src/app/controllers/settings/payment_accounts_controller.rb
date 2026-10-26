# Contas de pagamento do credor (12, R259 a R269): lista, cadastro, edição e exclusão, numa aba da configuração. A permissão 14 vale no
# credor da conta. O formulário se monta a partir do manifesto do fornecedor; segredo e arquivo entram e nunca voltam (R261).
module Settings
  class PaymentAccountsController < ApplicationController
    before_action :set_account, only: %i[edit update destroy]

    def index
      authorize PaymentAccount
      @several_tenants = manageable_tenants.size > 1
      @pagination = Pagination.new(policy_scope(PaymentAccount).includes(:tenant, :channel).order(:nickname), page: params[:page], per_page: params[:per_page])
      @accounts = @pagination.records
    end

    # Primeiro a escolha (credor, modalidade e fornecedor); com ela feita, o formulário do manifesto.
    def new
      authorize PaymentAccount
      @tenants = manageable_tenants
      @account = PaymentAccount.new(choice_params.merge(environment: "sandbox"))
      @chosen = choice_complete?(@account)
      load_channels
    end

    def create
      @tenants = manageable_tenants
      tenant = @tenants.find_by(id: permitted_params[:tenant_id]) or return head(:not_found)
      authorize PaymentAccount.new(tenant: tenant), :create?
      @account = manager.create(tenant: tenant, channel: tenant.payment_channels.find_by(id: permitted_params[:channel_id]), modality: permitted_params[:modality],
                                provider: permitted_params[:provider], environment: permitted_params[:environment], nickname: permitted_params[:nickname], values: values)
      redirect_to edit_settings_payment_account_path(@account), notice: t(".done", nickname: @account.nickname), status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      @account = error.record
      @chosen = true
      load_channels
      render :new, status: :unprocessable_content
    end

    def edit
      @secret = flash[:webhook_secret]
      response.headers["Cache-Control"] = "no-store" if @secret
      load_history
    end

    def update
      manager.update(@account, nickname: permitted_params[:nickname], channel: @account.tenant.payment_channels.find_by(id: permitted_params[:channel_id]), values: values)
      redirect_to edit_settings_payment_account_path(@account), notice: t(".done", nickname: @account.nickname), status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      @account = error.record
      load_history
      render :edit, status: :unprocessable_content
    end

    def destroy
      nickname = @account.nickname
      manager.destroy(@account)
      panel_finish(settings_payment_accounts_path, notice: t(".done", nickname: nickname), navegar: true)
    end

    private
      def set_account
        @account = PaymentAccount.includes(:tenant, :channel).find(params[:id])
        authorize @account
      end

      def manageable_tenants = Tenant.where(id: Current.user.tenant_ids_with("change_financial_policies")).order(:name)

      def manager = Payments::AccountManager.new(Current.user)

      def load_channels = @channels = @account.tenant_id ? PaymentChannel.where(tenant_id: @account.tenant_id, active: true).order(:code) : PaymentChannel.none

      def load_history
        @history = Change.where(tenant_id: @account.tenant_id, subject_type: "payment_account", subject_id: @account.id).includes(:user).order(occurred_at: :desc, id: :desc).limit(40)
      end

      # Parâmetros: os fixos mais os campos do manifesto do fornecedor da conta (segredos e arquivos em grupos próprios).
      def permitted_params
        @permitted_params ||= begin
          fixed = %i[tenant_id channel_id modality provider environment nickname]
          fields = account_fields
          groups = { config: fields.reject(&:secret?), secrets: fields.select { |f| f.type == "secret" }, files: fields.select(&:file?) }
                   .transform_values { |list| list.map { |field| field.name.to_sym } }.reject { |_group, names| names.empty? }
          params.expect(payment_account: [ *fixed, groups ])
        end
      end

      def values
        permitted = permitted_params
        { config: permitted[:config].to_h, secrets: permitted[:secrets].to_h, files: permitted[:files].to_h }
      end

      # Campos do manifesto: os da conta que se edita ou, no cadastro, os do fornecedor e da modalidade escolhidos.
      def account_fields
        provider, modality = @account ? [ @account.provider, @account.modality ] : [ params.dig(:payment_account, :provider), params.dig(:payment_account, :modality) ]
        Payments::Providers.known?(provider) && Payments::Providers::MODALITIES.include?(modality.to_s) ? Payments::Providers.manifest(provider).fields_for(modality) : []
      end

      def choice_params = params.permit(:tenant_id, :modality, :provider).to_h.symbolize_keys.select { |key, value| value.present? && (key != :provider || Payments::Providers.known?(value)) }

      def choice_complete?(account) = account.tenant_id.present? && account.modality.present? && account.provider.present? && manageable_tenants.exists?(account.tenant_id) &&
                                      Payments::Providers::MODALITIES.include?(account.modality) && account.adapter.supports?(account.modality)
  end
end
