module Agreements
  # Recusar a proposta pendente, com motivo (11, R216): os títulos ficam livres.
  class RefusalsController < ApplicationController
    def create
      agreement = Agreement.includes(:tenant).find(params[:agreement_id])
      authorize agreement, :refuse?
      Agreements::Reviewer.new(Current.user).refuse(agreement, params.expect(agreement: [ :reason ])[:reason])
      redirect_back_or_to agreement_path(agreement), notice: t(".done"), status: :see_other
    rescue Agreements::Refused => error
      redirect_back_or_to agreement_path(agreement), alert: error.message, status: :see_other
    end
  end
end
