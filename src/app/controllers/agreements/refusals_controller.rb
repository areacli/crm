module Agreements
  # Recusar a proposta pendente, com motivo (11, R216): os títulos ficam livres. O motivo se pede num modal pequeno.
  class RefusalsController < ApplicationController
    before_action :set_agreement

    def new
      authorize @agreement, :refuse?
    end

    def create
      authorize @agreement, :refuse?
      Agreements::Reviewer.new(Current.user).refuse(@agreement, params.expect(agreement: [ :reason ])[:reason])
      panel_finish(agreement_path(@agreement), notice: t(".done"), atualizar: true, eventos: %w[cable:agreements-changed])
    rescue Agreements::Refused => error
      panel_error(error.message, agreement_path(@agreement))
    end

    private
      def set_agreement = @agreement = Agreement.includes(:tenant).find(params[:agreement_id])
  end
end
