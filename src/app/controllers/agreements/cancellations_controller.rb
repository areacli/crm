module Agreements
  # Cancelar a proposta ainda não aceita, com motivo obrigatório (11, R218, DA33): qualquer usuário com "negociar acordos" no credor. O motivo se pede num modal pequeno.
  class CancellationsController < ApplicationController
    before_action :set_agreement

    def new
      authorize @agreement, :cancel?
    end

    def create
      authorize @agreement, :cancel?
      Agreements::Canceller.new(Current.user).cancel(@agreement, params.fetch(:agreement, {})[:reason])
      panel_finish(agreement_path(@agreement), notice: t(".done"), atualizar: true, eventos: %w[cable:agreements-changed])
    rescue Agreements::Refused => error
      panel_error(error.message, agreement_path(@agreement))
    end

    private
      def set_agreement = @agreement = Agreement.includes(:tenant).find(params[:agreement_id])
  end
end
