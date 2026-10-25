module Promises
  # Cancelar a promessa aberta ou pendente, com motivo obrigatório (10, R200): a permissão 15 no credor da promessa; quem não a tem recebe "não encontrado"
  # e a recusa fica registrada (R33). Os títulos ficam livres, sujeitos à carência; os já pagos pela promessa continuam pagos.
  class CancellationsController < ApplicationController
    def create
      promise = PaymentPromise.includes(:tenant).find(params[:promise_id])
      authorize promise, :cancel?
      Promises::Canceller.new(Current.user).cancel(promise, params.fetch(:promise, {})[:reason])
      redirect_back_or_to customer_path(promise.customer, anchor: "promessas"), notice: t(".done"), status: :see_other
    rescue Promises::Refused => error
      redirect_back_or_to customer_path(promise.customer, anchor: "promessas"), alert: error.message, status: :see_other
    end
  end
end
