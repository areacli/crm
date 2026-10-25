module Agreements
  # Reverter o acordo em dois passos (11, R239): `create` abre a reversão (estorna as liquidações e marca o acordo), `update` conclui (cancela) e `destroy` desiste (V4). Só quem tem
  # "administrar acordos" no credor; o motivo é obrigatório na abertura.
  class ReversionsController < ApplicationController
    before_action :load_agreement

    def create
      authorize @agreement, :revert?
      Agreements::Reversion.new(Current.user).open!(@agreement, params.fetch(:reversion, {})[:reason])
      redirect_to agreement_path(@agreement), notice: t(".done", number: @agreement.number), status: :see_other
    rescue Agreements::Refused => error
      redirect_to agreement_path(@agreement), alert: error.message, status: :see_other
    end

    def update
      authorize @agreement, :conclude?
      Agreements::Reversion.new(Current.user).conclude!(@agreement)
      redirect_to agreement_path(@agreement), notice: t(".done", number: @agreement.number), status: :see_other
    rescue Agreements::Refused => error
      redirect_to agreement_path(@agreement), alert: error.message, status: :see_other
    end

    def destroy
      authorize @agreement, :desist?
      Agreements::Reversion.new(Current.user).desist!(@agreement)
      redirect_to agreement_path(@agreement), notice: t(".done", number: @agreement.number), status: :see_other
    rescue Agreements::Refused => error
      redirect_to agreement_path(@agreement), alert: error.message, status: :see_other
    end

    private
      def load_agreement = @agreement = Agreement.includes(:tenant).find(params[:agreement_id])
  end
end
