module Checkouts
  # O pagamento no cartão (R278): o navegador envia só o `payment_token` que a biblioteca do fornecedor gerou e o número de parcelas. O resultado volta
  # na própria resposta (um trecho que substitui a área de pagamento); nada de dado de cartão passa por aqui. Limite de tentativas por IP e por link
  # (teste de cartões é o abuso comum de página de pagamento).
  class CardPaymentsController < CheckoutBaseController
    rate_limit to: 10, within: 5.minutes, name: "card_by_ip", only: :create, with: -> { head :too_many_requests }
    rate_limit to: 20, within: 1.hour, name: "card_by_link", only: :create, by: -> { params[:token].to_s }, with: -> { head :too_many_requests }

    def create
      payment_token, installments = params.expect(:payment_token, :installments)
      # A bandeira (só o nome, que o navegador descobriu) vai para o fornecedor que calcula os juros do parcelamento por ela (12, revisão 5).
      outcome = Payments::CardCharger.new.charge(checkout, payment_token: payment_token, installments: installments, brand: params[:brand])
      status = outcome.kind.in?(%i[invalid not_payable]) ? :unprocessable_content : :ok
      render partial: "checkouts/options", locals: { checkout: checkout.reload, card: Payments::CardForm.for(checkout), outcome: outcome }, status: status
    end
  end
end
