module Agreements
  # Reverter o acordo em dois passos (11, R239): `create` abre a reversão (estorna as liquidações e marca o acordo), `update` conclui (cancela) e `destroy` desiste (V4). Só quem tem
  # "administrar acordos" no credor; o motivo é obrigatório na abertura (modal pequeno). Concluir e desistir são confirmações do painel.
  class ReversionsController < ApplicationController
    before_action :load_agreement

    def new
      authorize @agreement, :revert?
    end

    def create
      authorize @agreement, :revert?
      Agreements::Reversion.new(Current.user).open!(@agreement, params.fetch(:reversion, {})[:reason])
      panel_finish(agreement_path(@agreement), notice: t(".done", number: @agreement.number), atualizar: true, eventos: %w[cable:agreements-changed])
    rescue Agreements::Refused => error
      panel_error(error.message, agreement_path(@agreement))
    end

    def update
      authorize @agreement, :conclude?
      Agreements::Reversion.new(Current.user).conclude!(@agreement)
      panel_finish(agreement_path(@agreement), notice: t(".done", number: @agreement.number), atualizar: true, eventos: %w[cable:agreements-changed])
    rescue Agreements::Refused => error
      panel_refuse(agreement_path(@agreement), error.message)
    end

    def destroy
      authorize @agreement, :desist?
      Agreements::Reversion.new(Current.user).desist!(@agreement)
      panel_finish(agreement_path(@agreement), notice: t(".done", number: @agreement.number), atualizar: true, eventos: %w[cable:agreements-changed])
    rescue Agreements::Refused => error
      panel_refuse(agreement_path(@agreement), error.message)
    end

    private
      def load_agreement = @agreement = Agreement.includes(:tenant).find(params[:agreement_id])
  end
end
