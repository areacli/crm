module Agreements
  # Aprovar a proposta pendente (11, R216): a 16 no credor, limites atuais que a cobririam, e nunca quem a montou; sem isso a recusa vira "não encontrado" e fica registrada (R33).
  class ApprovalsController < ApplicationController
    def create
      agreement = Agreement.includes(:tenant).find(params[:agreement_id])
      authorize agreement, :approve?
      Agreements::Reviewer.new(Current.user).approve(agreement)
      redirect_back_or_to agreement_path(agreement), notice: t(".done", number: agreement.number), status: :see_other
    rescue Agreements::Refused => error
      redirect_back_or_to agreement_path(agreement), alert: error.message, status: :see_other
    end
  end
end
