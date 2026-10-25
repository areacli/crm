module Promises
  # Aprovar a promessa pendente (10, R192): a 7, a alçada que cobriria o prazo pedido e nunca quem a registrou, conferidas no credor da promessa; sem isso a
  # recusa vira "não encontrado" e fica registrada (R33).
  class ApprovalsController < ApplicationController
    def create
      promise = PaymentPromise.includes(:tenant).find(params[:promise_id])
      authorize promise, :approve?
      Promises::Reviewer.new(Current.user).approve(promise)
      redirect_back_or_to customer_path(promise.customer, anchor: "promessas"), notice: t(".done", number: promise.number), status: :see_other
    rescue Promises::Refused => error
      redirect_back_or_to customer_path(promise.customer, anchor: "promessas"), alert: error.message, status: :see_other
    end
  end
end
