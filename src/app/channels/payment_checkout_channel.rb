# Página pública de pagamento (12, R277): quem tem o link (o token) assina o canal dele, sem login. O canal transmite só o sinal "checkout-changed"
# (o pagamento foi aprovado ou confirmado); a página busca o trecho de novo pelo htmx. Token inexistente, vencido ou cancelado é rejeitado, sem dizer qual.
class PaymentCheckoutChannel < ApplicationCable::Channel
  def subscribed
    checkout = PaymentCheckout.find_by(token: params[:token].to_s)
    return reject unless checkout&.available?

    stream_for checkout
  end
end
