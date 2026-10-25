# Configuração da carteira, por credor: faixas de atraso (R18), tratamento do a vencer (R20), política de divergência de valor (05, R94, R104) e correção na tela ou carga (06, R117). Sem seleção de credor: cada um tem o seu bloco.
module Settings
  class PortfoliosController < ApplicationController
    def show
      @settings = settings_scope
      authorize TenantSetting
    end

    def update
      tenant = Tenant.find(params[:tenant_id])
      # A política de divergência é financeira (permissão 14, no credor); faixas e a vencer são da permissão 4.
      authorize tenant.setting, :update?, policy_class: (params[:section] == "discrepancy" ? PaymentSettingPolicy : TenantSettingPolicy)
      service = Portfolio::SettingsService.new
      case params[:section]
      when "brackets"
        rows = params.fetch(:brackets, []).map { |row| row.permit(:from, :to).to_h }.reject { |row| row["from"].blank? && row["to"].blank? }
        service.update_brackets(tenant, rows, Current.user)
      when "upcoming"
        service.update_upcoming_display(tenant, params[:upcoming_display], Current.user)
      when "discrepancy"
        service.update_discrepancy_policy(tenant, params[:discrepancy_policy], Current.user)
      when "correction"
        service.update_correction_policy(tenant, params[:correction_policy], Current.user)
      else
        return head :bad_request
      end
      redirect_to settings_portfolio_path, notice: "Configuração de #{tenant.name} salva."
    rescue Portfolio::InvalidBrackets, ActiveRecord::RecordInvalid => error
      @settings = settings_scope
      @error = { tenant_id: tenant.id, message: "#{error.message.capitalize}." }
      render :show, status: :unprocessable_content
    end

    private
      def settings_scope = policy_scope(TenantSetting).includes(:tenant).joins(:tenant).order("tenants.name")
  end
end
