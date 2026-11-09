module Promises
  # Aprovar a promessa pendente (10, R192): a 7, a alçada que cobriria o prazo pedido e nunca quem a registrou, conferidas no credor da promessa; sem isso a
  # recusa vira "não encontrado" e fica registrada (R33).
  class ApprovalsController < ApplicationController
    def create
      promise = PaymentPromise.includes(:tenant).find(params[:promise_id])
      authorize promise, :approve?
      Promises::Reviewer.new(Current.user).approve(promise)
      # Na SPA (decisão 0028), o fim vem no `X-CRM-Evento`: o aviso e a tela refeita (a ficha ou a lista de pendentes).
      return panel_finish(customer_path(promise.customer), notice: t(".done", number: promise.number), atualizar: true) if spa?

      redirect_back_or_to customer_path(promise.customer, anchor: "promessas"), notice: t(".done", number: promise.number), status: :see_other
    rescue Promises::Refused => error
      return panel_refuse(customer_path(promise.customer), error.message) if spa?

      redirect_back_or_to customer_path(promise.customer, anchor: "promessas"), alert: error.message, status: :see_other
    end
  end
end
