module Checkouts
  # As parcelas do cartão, pela bandeira (que o navegador descobre sem enviar o número do cartão). Só o nome da bandeira chega aqui.
  class InstallmentsController < CheckoutBaseController
    def index
      render partial: "checkouts/installments", locals: { checkout: checkout, card: Payments::CardForm.for(checkout, brand: params[:brand].to_s.first(20)) }
    end
  end
end
