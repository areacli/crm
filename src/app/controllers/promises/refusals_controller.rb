module Promises
  # Recusar a promessa pendente, com motivo (10, R192): os títulos ficam livres, sujeitos à carência (R188). O motivo se pede num modal pequeno.
  class RefusalsController < ApplicationController
    before_action :set_promise

    def new
      authorize @promise, :refuse?
    end

    def create
      authorize @promise, :refuse?
      Promises::Reviewer.new(Current.user).refuse(@promise, params.expect(promise: [ :reason ])[:reason])
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
