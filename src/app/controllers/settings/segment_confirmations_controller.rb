module Settings
  # Confirmação da mudança de segmentos (R154): vale na hora (DS3). Recusa a conferência velha.
  class SegmentConfirmationsController < ApplicationController
    include SegmentReview

    def create
      tenant = tenant_for_change(params[:tenant_id])
      ::Segments::Applier.new(Current.user).confirm(tenant, params.expect(confirmation: [ :token ])[:token])
      redirect_to settings_segments_path, notice: t("segments.flash.confirmed", tenant: tenant.name), status: :see_other
    rescue ::Segments::Refused => error
      redirect_to settings_segments_path, alert: error.message, status: :see_other
    end
  end
end
