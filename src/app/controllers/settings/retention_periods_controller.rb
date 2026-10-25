module Settings
  # Prazo de guarda dos dados do cliente, em anos (07, R136), na aba Dados do credor: a permissão 4 vale no credor editado. Vale para a próxima
  # execução da tarefa diária.
  class RetentionPeriodsController < ApplicationController
    def update
      tenant = Tenant.find(params[:tenant_id])
      authorize tenant.setting, :update?, policy_class: TenantSettingPolicy
      years = params.expect(retention: [ :years ])[:years].to_s
      raise Access::Refused, t(".invalid") unless years.match?(/\A\d{1,2}\z/) && years.to_i.between?(1, 50)

      setting = tenant.setting
      before = setting.retention_years
      setting.update!(retention_years: years.to_i)
      unless before == setting.retention_years
        Change.create!(tenant: tenant, user: Current.user, subject_type: "settings", subject_id: tenant.id, event: "retention_years_changed", field: "retention_years",
                       before: before.to_s, after: years, origin: "screen")
        Titular::Broadcast.changed(tenant)
      end
      redirect_to settings_tenant_registry_path, notice: t(".done", tenant: tenant.name), status: :see_other
    end
  end
end
