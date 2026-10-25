module Settings
  # Variáveis de acordo de cada segmento (11, R207; permissão 14): teto de desconto por componente (parcelado e à vista), parcelas, parcela mínima, entrada mínima, prazo
  # da entrada, validade, tolerância e dias de quebra. Gravam sem conferência do impacto, com registro; baixar um máximo baixa os limites dos perfis que passavam dele (R209).
  class AgreementVariablesController < ApplicationController
    FIELDS = %i[max_installments min_installment min_down_payment_pct down_payment_days validity_days tolerance_days break_days].freeze

    def update
      tenant = Tenant.find(params[:tenant_id])
      authorize tenant.setting, :update?, policy_class: AgreementSettingPolicy
      segments = tenant.segments.ids.filter_map do |id|
        row = params.dig(:segments, id.to_s) or next
        [ id, row.permit(*FIELDS, caps: { installment: Agreements::Caps::COMPONENTS, cash: Agreements::Caps::COMPONENTS }).to_h.deep_symbolize_keys.tap { |hash| hash[:caps] = hash[:caps]&.deep_stringify_keys } ]
      end.to_h
      Agreements::Settings.new(Current.user).update_variables(tenant, segments)
      redirect_to settings_promises_path, notice: t(".done", tenant: tenant.name), status: :see_other
    rescue Agreements::Refused, ActiveRecord::RecordInvalid => error
      redirect_to settings_promises_path, alert: error.message, status: :see_other
    end
  end
end
