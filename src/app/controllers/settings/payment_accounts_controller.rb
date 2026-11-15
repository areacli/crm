# Integrações do credor (12, R259 a R269; antes "contas de pagamento"): cadastro, edição, troca de fornecedor e exclusão. A lista é a página
# "Meios de pagamento" (16, revisão 1, R373a), com um quadro por meio. A permissão 14 vale no credor da integração. O formulário se monta a partir do
# manifesto do fornecedor, nos grupos Acesso e Cobrança (R373b); segredo e arquivo entram e nunca voltam (R261).
module Settings
  class PaymentAccountsController < ApplicationController
    before_action :set_account, only: %i[edit update destroy]

    # A escolha vem do quadro do meio: credor, meio e ambiente no endereço (ou a integração que se troca, `substitui`); o fornecedor se escolhe aqui,
    # entre os que emitem o meio. Com ele escolhido, o formulário do manifesto.
    def new
      authorize PaymentAccount
      @tenants = manageable_tenants
      @replaced = replaced_account
      @account = PaymentAccount.new(choice_params.merge(environment: choice_params[:environment] || "sandbox"))
      @account.assign_attributes(tenant_id: @replaced.tenant_id, modality: @replaced.modality, environment: @replaced.environment) if @replaced
      @providers = provider_choices(@account.modality)
      @account.provider = nil unless @account.provider.in?(@providers)
      @chosen = choice_complete?(@account)
      @account.nickname = nickname_for(@account)
      # A conta digitada fica quando o fornecedor muda; numa troca, começa vazia (o fornecedor novo tem outra conta).
      @account.account_code = params.dig(:payment_account, :account_code).to_s.strip.presence
      # Na SPA, a mudança da escolha pede só os campos que dependem dela (`data-spa-dependentes`).
      render partial: "settings/payment_accounts/dependent_blocks" if spa? && params[:payment_account].present?
    end

    def create
      @tenants = manageable_tenants
      tenant = @tenants.find_by(id: permitted_params[:tenant_id]) or return head(:not_found)
      authorize PaymentAccount.new(tenant: tenant), :create?
      @replaced = replaced_account
      @account = manager.create(tenant: tenant, modality: permitted_params[:modality],
                                provider: permitted_params[:provider], environment: permitted_params[:environment], nickname: permitted_params[:nickname],
                                account_code: permitted_params[:account_code], values: values,
                                replaces: @replaced)
      # A aba da nova integração passa a ser a da integração criada.
      panel_finish(edit_settings_payment_account_path(@account), notice: t(".done", nickname: @account.nickname), navegar: true, mesma_aba: true)
    rescue ActiveRecord::RecordInvalid => error
      @account = error.record
      @chosen = true
      @providers = provider_choices(@account.modality)
      render :new, status: :unprocessable_content
    end

    def edit
      @secret = flash[:webhook_secret]
      response.headers["Cache-Control"] = "no-store" if @secret
      load_history
    end

    def update
      manager.update(@account, nickname: permitted_params[:nickname], account_code: permitted_params[:account_code], values: values)
      panel_finish(edit_settings_payment_account_path(@account), notice: t(".done", nickname: @account.nickname), atualizar: true)
    rescue ActiveRecord::RecordInvalid => error
      @account = error.record
      load_history
      render :edit, status: :unprocessable_content
    end

    # Excluir (R269) também é o "Desistir" da troca à espera da conexão (R373c): a nova sai, e a anterior continua como estava.
    def destroy
      nickname = @account.nickname
      tenant_id = @account.tenant_id
      manager.destroy(@account)
      panel_finish(settings_payment_methods_path(credor: tenant_id), notice: t(".done", nickname: nickname), navegar: true, mesma_aba: true)
    end

    private
      def set_account
        @account = PaymentAccount.includes(:tenant).find(params[:id])
        authorize @account
      end

      def manageable_tenants = Tenant.where(id: Current.user.tenant_ids_with("change_financial_policies")).order(:name)

      def manager = Payments::AccountManager.new(Current.user)

      def load_history
        @history = Change.where(tenant_id: @account.tenant_id, subject_type: "payment_account", subject_id: @account.id).includes(:user).order(occurred_at: :desc, id: :desc).limit(40)
      end

      # Parâmetros: os fixos mais os campos do manifesto do fornecedor da conta (segredos e arquivos em grupos próprios).
      def permitted_params
        @permitted_params ||= begin
          fixed = %i[tenant_id modality provider environment nickname account_code nickname_suggested replaces_id]
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

      # A escolha vem na consulta (o link "Criar integração" do quadro do meio) ou no formulário (`payment_account[...]`, quando a escolha muda na SPA).
      def choice_params
        @choice_params ||= begin
          query = { tenant_id: params[:credor], modality: FilterValue.from_url(params[:meio] || params[:modalidade]), environment: FilterValue.from_url(params[:ambiente]), provider: params[:fornecedor] }
          form = params.fetch(:payment_account, {}).permit(:tenant_id, :modality, :environment, :provider).to_h.compact_blank.symbolize_keys
          query.merge(form).select do |key, value|
            value.present? && case key
                              when :provider then Payments::Providers.known?(value)
                              when :modality then Payments::Providers::MODALITIES.include?(value)
                              when :environment then PaymentAccount.environments.key?(value)
                              else true
                              end
          end
        end
      end

      # A integração que se troca ("Trocar fornecedor", R373c): só a ativa, de credor em que a pessoa tem a 14.
      def replaced_account
        id = params[:substitui].presence || params.dig(:payment_account, :replaces_id).presence
        return unless id

        account = PaymentAccount.find(id)
        authorize account, :update?
        account
      end

      # Os fornecedores instalados que emitem o meio, sem o da integração que se troca.
      def provider_choices(modality)
        return [] unless Payments::Providers::MODALITIES.include?(modality.to_s)

        Payments::Providers.for_modality(modality) - [ @replaced&.provider ]
      end

      # Apelido sugerido, "<meio> <fornecedor>" (e o ambiente em homologação), único no credor. O que a pessoa digitou fica; a sugestão anterior,
      # que ela não mexeu, acompanha a troca do fornecedor.
      def nickname_for(account)
        typed = params.dig(:payment_account, :nickname).to_s.strip
        suggested = params.dig(:payment_account, :nickname_suggested).to_s.strip
        return typed if typed.present? && typed != suggested
        return typed unless account.provider.present? && account.modality.present? && account.tenant_id.present?

        base = [ t("payments.accounts.modalities.#{account.modality}"), provider_name(account.provider), (t("payments.accounts.environments.sandbox").downcase if account.sandbox?) ].compact.join(" ")
        taken = PaymentAccount.where(tenant_id: account.tenant_id).pluck(:nickname)
        candidates = [ base, *(2..20).map { |number| "#{base} #{number}" } ]
        @nickname_suggested = candidates.find { |candidate| !candidate.in?(taken) } || base
      end

      def provider_name(provider) = helpers.provider_name(provider)

      def choice_complete?(account) = account.tenant_id.present? && account.modality.present? && account.provider.present? && manageable_tenants.exists?(account.tenant_id) &&
                                      Payments::Providers::MODALITIES.include?(account.modality) && account.adapter.supports?(account.modality)
  end
end
