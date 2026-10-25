module Settings
  # Parâmetros dos acordos do credor e o valor próprio de cada segmento (11, R207a, R246; permissão 14): taxa e método do parcelamento, convenção de dias e base da
  # multa dos títulos de acordo. Gravam sem conferência do impacto, com registro de antes e depois.
  class AgreementParametersController < ApplicationController
    def update
      tenant = Tenant.find(params[:tenant_id])
      authorize tenant.setting, :update?, policy_class: AgreementSettingPolicy
      fields = %i[installment_rate_pct installment_method agreement_days_convention agreement_fine_base]
      values = params.expect(credor: fields).to_h
      overrides = tenant.segments.ids.filter_map do |id|
        row = params.dig(:segments, id.to_s) or next
        [ id, row.permit(*fields).to_h ]
      end.to_h
      Agreements::Settings.new(Current.user).update_parameters(tenant, values, overrides)
      redirect_to settings_segments_path, notice: t(".done", tenant: tenant.name), status: :see_other
    rescue Agreements::Refused, ActiveRecord::RecordInvalid => error
      redirect_to settings_segments_path, alert: error.message, status: :see_other
    end
  end
end
