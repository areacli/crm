module Settings
  # Prazo máximo de cada segmento e alçada de cada perfil (10, R189, R190): permissão 14 no credor. Baixar o prazo do segmento baixa as alçadas que passavam dele.
  class PromiseLimitsController < ApplicationController
    def update
      tenant = Tenant.find(params[:tenant_id])
      authorize tenant.setting, :update?, policy_class: PromiseSettingPolicy
      profile_ids = tenant.profiles.ids.map(&:to_s)
      segments = tenant.segments.ids.filter_map do |id|
        values = params.dig(:segments, id.to_s) or next
        [ id, { max_days: values[:max_days], limits: values.fetch(:limits, {}).permit(*profile_ids).to_h.symbolize_keys } ]
      end.to_h
      Promises::Settings.new(Current.user).update_limits(tenant, segments)
      redirect_to settings_promises_path, notice: t(".done", tenant: tenant.name), status: :see_other
    rescue Access::Refused => error
      redirect_to settings_promises_path, alert: error.message, status: :see_other
    end
  end
end
