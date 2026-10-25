# A página de pagamento do cliente (12, R277): o valor emitido (R280), Pix, boleto e cartão. Pública, pelo token.
class CheckoutsController < CheckoutBaseController
  def show
    PaymentCheckout.update_counters(checkout.id, access_count: 1)
    checkout.update_column(:last_accessed_at, Time.current)
    @card = Payments::CardForm.for(checkout)
  end
end
