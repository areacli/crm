module Promises
  # Recusar a promessa pendente, com motivo (10, R192): os títulos ficam livres, sujeitos à carência (R188).
  class RefusalsController < ApplicationController
    def create
      promise = PaymentPromise.includes(:tenant).find(params[:promise_id])
      authorize promise, :refuse?
      Promises::Reviewer.new(Current.user).refuse(promise, params.expect(promise: [ :reason ])[:reason])
      redirect_back_or_to customer_path(promise.customer, anchor: "promessas"), notice: t(".done"), status: :see_other
    rescue Promises::Refused => error
      redirect_back_or_to customer_path(promise.customer, anchor: "promessas"), alert: error.message, status: :see_other
    end
  end
end
