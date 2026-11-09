module Settings
  # Limites de cada perfil por item do enquadramento (11, R209, N23; permissão 14): teto de desconto por componente, parcelas, entrada mínima e os tetos em reais, sempre dentro das
  # variáveis do item. Gravam com registro; valem para as propostas novas.
  class AgreementLimitsController < ApplicationController
    FIELDS = %i[max_installments min_down_payment_pct ceiling_discount ceiling_value].freeze

    def update
      tenant = Tenant.find(params[:credor])
      authorize tenant.setting, :update?, policy_class: AgreementSettingPolicy
      permitted = FIELDS + [ { caps: { installment: Agreements::Caps::COMPONENTS, cash: Agreements::Caps::COMPONENTS } } ]
      limits = tenant.tiers.ids.filter_map do |tier_id|
        rows = params.dig(:limits, tier_id.to_s) or next
        profiles = tenant.profiles.ids.filter_map do |profile_id|
          row = rows[profile_id.to_s] or next
          [ profile_id, row.permit(*permitted).to_h.deep_symbolize_keys.tap { |hash| hash[:caps] = hash[:caps]&.deep_stringify_keys } ]
        end.to_h
        [ tier_id, profiles ]
      end.to_h
      Agreements::Settings.new(Current.user).update_limits(tenant, limits)
      redirect_to settings_promises_path, notice: t(".done", tenant: tenant.name), status: :see_other
    rescue Agreements::Refused, ActiveRecord::RecordInvalid => error
      redirect_to settings_promises_path, alert: error.message, status: :see_other
    end
  end
end
