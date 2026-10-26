module Agreements
  # Quebra manual do acordo (11, R238, DA12): quem tem "administrar acordos" no credor, com motivo. Só para acordo em atraso há mais que a tolerância, ou por fraude. Modal pequeno.
  class BreaksController < ApplicationController
    before_action :set_agreement

    def new
      authorize @agreement, :break?
    end

    def create
      authorize @agreement, :break?
      raw = params.fetch(:break, {})
      Agreements::Breaker.manual!(@agreement, Current.user, reason: raw[:reason], fraud: raw[:fraud].to_s == "1")
      panel_finish(agreement_path(@agreement), notice: t(".done", number: @agreement.number), atualizar: true, eventos: %w[cable:agreements-changed])
    rescue Agreements::Refused => error
      panel_error(error.message, agreement_path(@agreement))
    end

    private
      def set_agreement = @agreement = Agreement.includes(:tenant).find(params[:agreement_id])
  end
end
