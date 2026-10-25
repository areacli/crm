module Settings
  # Políticas dos acordos (11, tabela de políticas, R228a, R229; permissão 14): as da aba "Promessas e acordos" e as de crédito e pagamento da aba "Pagamentos". Valem
  # para as propostas novas, porque o acordo congela as dele (R210). Cada mudança fica registrada, com "Ver histórico".
  class AgreementPoliciesController < ApplicationController
    def update
      tenant = Tenant.find(params[:tenant_id])
      authorize tenant.setting, :update?, policy_class: AgreementSettingPolicy
      tab = params[:tab] == "payments" ? :payments : :agreements
      values = Agreements::Policies.keys(tab).filter_map do |key|
        raw = params.dig(:policies, key) or next
        entry = Agreements::Policies.entry(key)
        [ key, entry.kind == :choice ? raw.to_s : raw.permit(:kind, :value).to_h.symbolize_keys ]
      end.to_h
      Agreements::Settings.new(Current.user).update_policies(tenant, values)
      redirect_to(tab == :payments ? settings_payment_policy_path : settings_promises_path, notice: t(".done", tenant: tenant.name), status: :see_other)
    rescue Agreements::Refused => error
      redirect_to(tab == :payments ? settings_payment_policy_path : settings_promises_path, alert: error.message, status: :see_other)
    end
  end
end
