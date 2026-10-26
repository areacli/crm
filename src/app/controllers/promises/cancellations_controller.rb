module Promises
  # Cancelar a promessa aberta ou pendente, com motivo obrigatório (10, R200): a permissão 15 no credor da promessa; quem não a tem recebe "não encontrado"
  # e a recusa fica registrada (R33). Os títulos ficam livres, sujeitos à carência; os já pagos pela promessa continuam pagos. O motivo se pede num modal pequeno.
  class CancellationsController < ApplicationController
    before_action :set_promise

    def new
      authorize @promise, :cancel?
    end

    def create
      authorize @promise, :cancel?
      Promises::Canceller.new(Current.user).cancel(@promise, params.fetch(:promise, {})[:reason])
      panel_finish(back_path, notice: t(".done"), eventos: %w[cable:promises-changed])
    rescue Promises::Refused => error
      return redirect_back_or_to(back_path, alert: error.message, status: :see_other) unless panel_request?

      @error = error.message
      render :new, status: :unprocessable_content
    end

    private
      def set_promise = @promise = PaymentPromise.includes(:tenant).find(params[:promise_id])

      # Volta para a página de onde veio (ficha ou lista de pendentes), salvo se veio da própria página do formulário.
      def back_path
        origin = request.referer
        origin.present? && !origin.match?(%r{/(recusa|cancelamento)}) ? origin : customer_path(@promise.customer, aba: "promessas")
      end
  end
end
