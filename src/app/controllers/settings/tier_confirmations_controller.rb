module Settings
  # Confirmação de uma mudança no enquadramento financeiro (13, R272): vale na hora (DS3). Recusa a conferência velha e a expirada; a
  # expirada volta ao enquadramento com a mensagem (R284).
  class TierConfirmationsController < ApplicationController
    include TierReview

    def create
      tenant = tenant_for_change(params[:tenant_id])
      ::Tiers::Applier.new(Current.user).confirm(tenant, params.expect(confirmation: [ :token ])[:token])
      redirect_to settings_tiers_path, notice: t("tiers.flash.confirmed", tenant: tenant.name), status: :see_other
    rescue ::Tiers::Refused => error
      redirect_to settings_tiers_path, alert: error.message, status: :see_other
    end
  end
end
