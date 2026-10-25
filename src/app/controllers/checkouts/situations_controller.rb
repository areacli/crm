module Checkouts
  # O trecho de situação e das formas de pagar, que a página busca de novo quando o canal avisa que o estado mudou (cartão aprovado, pagamento confirmado).
  class SituationsController < CheckoutBaseController
    def show
      @card = Payments::CardForm.for(checkout)
      render partial: "checkouts/options", locals: { checkout: checkout, card: @card }
    end
  end
end
