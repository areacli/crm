# Configuração da carteira, por credor: faixas de atraso (R18) e tratamento do a vencer (R20). Sem seleção de credor: cada um tem o seu bloco.
module Settings
  class PortfoliosController < ApplicationController
    def show
      @settings = settings_scope
      authorize TenantSetting
    end

    def update
      tenant = Tenant.find(params[:tenant_id])
      authorize tenant.setting, :update?
      service = Portfolio::SettingsService.new
      case params[:section]
      when "brackets"
        rows = params.fetch(:brackets, []).map { |row| row.permit(:from, :to).to_h }.reject { |row| row["from"].blank? && row["to"].blank? }
        service.update_brackets(tenant, rows, Current.user)
      when "upcoming"
        service.update_upcoming_display(tenant, params[:upcoming_display], Current.user)
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
