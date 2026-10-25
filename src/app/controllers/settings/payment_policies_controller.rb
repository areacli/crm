# Políticas de pagamento do credor (R46, R46a, R62a, R64), numa aba da configuração: um bloco por credor em que a pessoa tem a permissão 14.
module Settings
  class PaymentPoliciesController < ApplicationController
    def show
      authorize TenantSetting, :show?, policy_class: PaymentSettingPolicy
      @settings = settings_scope
    end

    def update
      tenant = Tenant.find(params[:tenant_id])
      authorize tenant.setting, :update?, policy_class: PaymentSettingPolicy
      values = params.expect(tenant_setting: TenantSetting::PAYMENT_POLICIES)
      Payments::PolicySettings.new(Current.user).update(tenant, values.to_h)
      redirect_to settings_payment_policy_path, notice: t(".done", tenant: tenant.name), status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      @settings = settings_scope
      @error = { tenant_id: tenant.id, message: "#{error.message.capitalize}." }
      render :show, status: :unprocessable_content
    end

    private
      def settings_scope = PaymentSettingPolicy::Scope.new(Current.user, TenantSetting).resolve.includes(:tenant).joins(:tenant).order("tenants.name")
  end
end
