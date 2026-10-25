module Settings
  # Políticas das promessas do credor (10, tabela de políticas, permissão 14): vale para as promessas novas (R187).
  class PromisePoliciesController < ApplicationController
    def update
      tenant = Tenant.find(params[:tenant_id])
      authorize tenant.setting, :update?, policy_class: PromiseSettingPolicy
      values = params.expect(tenant_setting: TenantSetting::PROMISE_POLICIES.map(&:to_sym))
      Promises::Settings.new(Current.user).update_policies(tenant, values.to_h)
      redirect_to settings_promises_path, notice: t(".done", tenant: tenant.name), status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      redirect_to settings_promises_path, alert: "#{error.message.capitalize}.", status: :see_other
    end
  end
end
