require "test_helper"

# Aviso por fornecedor (12, revisão 6, R284w): a rota única do Mercado Pago confere a assinatura com o segredo do webhook da aplicação e guarda o aviso na
# integração conectada à conta do aviso que emitiu o pedido; assinatura errada é 401; conta ou pedido que nenhuma integração tem é 202 sem gravar.
class MercadopagoWebhooksTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    with_mercadopago_app
    @pix = make_mercadopago_account(@alfa, modality: "pix")
    @boleto = make_mercadopago_account(@alfa, modality: "boleto")
    bill = make_bill(@alfa, number: "NF-MP-1", amount_cents: 125_000)
    @instrument = PaymentInstrument.create!(tenant: @alfa, account: @pix, provider: "mercadopago", customer: bill.customer, kind: "pix", amount_cents: 125_000, due_on: Date.current + 5,
                                            custom_id: "A" * 32, object: bill, state: "active", external_id: MercadopagoHttpHelper::ORDER_ID, **Payments::Payer.snapshot(bill.customer))
  end

  def notify(order_id: MercadopagoHttpHelper::ORDER_ID, user_id: MercadopagoHttpHelper::SELLER, headers: nil, action: "order.processed")
    body = { "type" => "order", "action" => action, "data" => { "id" => order_id }, "user_id" => user_id, "live_mode" => true }.to_json
    post "/webhooks/pagamentos/fornecedores/mercadopago?data.id=#{order_id}&type=order", params: body,
                                                                                         headers: { "CONTENT_TYPE" => "application/json" }.merge(headers || mercadopago_signature(order_id))
  end

  test "aviso assinado vai à integração conectada à conta que emitiu o pedido, uma vez só" do
    assert_enqueued_jobs 1, only: ProcessPaymentEventJob do
      notify
      notify
    end
    assert_response :accepted
    event = PaymentEvent.sole
    assert_equal [ @pix.id, "#{MercadopagoHttpHelper::ORDER_ID}:processed", "paid" ], [ event.account_id, event.event_id, event.kind ]
  end

  test "assinatura errada: 401, registrado, nada gravado" do
    notify(headers: mercadopago_signature(MercadopagoHttpHelper::ORDER_ID, secret: "outro"))
    assert_response :unauthorized
    assert_equal 0, PaymentEvent.count
    assert AccessEvent.where(event: "webhook_refused").exists?
  end

  test "conta ou pedido que nenhuma integração tem: 202 sem gravar" do
    notify(user_id: "999")
    assert_response :accepted
    notify(order_id: "ORD-DE-OUTRO")
    assert_response :accepted
    assert_equal 0, PaymentEvent.count
  end

  test "fornecedor que avisa por integração não tem esta rota" do
    post "/webhooks/pagamentos/fornecedores/efi", params: "{}", headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :not_found
  end
end
