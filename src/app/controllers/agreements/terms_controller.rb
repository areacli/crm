module Agreements
  # O termo do acordo para imprimir ou salvar pelo navegador (11, R219): o rascunho da proposta aprovada, ou o guardado no aceite. Quem abre o acordo (16 no credor).
  class TermsController < ApplicationController
    def show
      @agreement = Agreement.includes(:tenant, :customer, agreement_bills: %i[bill contract]).find(params[:agreement_id])
      authorize @agreement, :term?
      @term = @agreement.term_snapshot.presence || Agreements::Term.build(@agreement)
      return redirect_to(agreement_path(@agreement), alert: t(".not_ready"), status: :see_other) if @agreement.state_pending? || @term["missing"].any?

      render layout: "impressao"
    end
  end
end
