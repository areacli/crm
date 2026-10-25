module Agreements
  # Cancelar a proposta ainda não aceita, com motivo obrigatório (11, R218, DA33): qualquer usuário com "negociar acordos" no credor.
  class CancellationsController < ApplicationController
    def create
      agreement = Agreement.includes(:tenant).find(params[:agreement_id])
      authorize agreement, :cancel?
      Agreements::Canceller.new(Current.user).cancel(agreement, params.fetch(:agreement, {})[:reason])
      redirect_back_or_to agreement_path(agreement), notice: t(".done"), status: :see_other
    rescue Agreements::Refused => error
      redirect_back_or_to agreement_path(agreement), alert: error.message, status: :see_other
    end
  end
end
