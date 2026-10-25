module Agreements
  # Quebra manual do acordo (11, R238, DA12): quem tem "administrar acordos" no credor, com motivo. Só para acordo em atraso há mais que a tolerância, ou por fraude.
  class BreaksController < ApplicationController
    def create
      agreement = Agreement.includes(:tenant).find(params[:agreement_id])
      authorize agreement, :break?
      raw = params.fetch(:break, {})
      Agreements::Breaker.manual!(agreement, Current.user, reason: raw[:reason], fraud: raw[:fraud].to_s == "1")
      redirect_back_or_to agreement_path(agreement), notice: t(".done", number: agreement.number), status: :see_other
    rescue Agreements::Refused => error
      redirect_back_or_to agreement_path(agreement), alert: error.message, status: :see_other
    end
  end
end
