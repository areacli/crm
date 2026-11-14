require "test_helper"

# Página `/pagar` com cartão do Mercado Pago (12, revisão 6, R284ab): o formulário monta os campos do Mercado Pago, a política libera só os domínios dele
# que o adaptador declara, e o servidor recebe o token, a bandeira e as parcelas; o pedido leva o e-mail do pagador, sem 3DS.
class MercadopagoCheckoutTest < ActionDispatch::IntegrationTest
  setup do
    @alfa = tenants(:alfa)
    @customer = make_customer(@alfa)
    add_contact(@customer, "email", "maria@exemplo.com.br")
    make_mercadopago_account(@alfa, modality: "card", environment: "production")
    @checkout = Payments::Checkouts.create(tenant: @alfa, customer: Customer.find(@customer.id), object: bill_for(@customer, amount_cents: 100_000), amount_cents: 100_000, card: true)
  end

  test "a página monta os campos do Mercado Pago e libera só os domínios dele" do
    get checkout_path(@checkout)
    assert_response :success
    form = Nokogiri::HTML5(response.body).at_css("form[data-cartao]")
    assert form.key?("data-montar")
    assert_equal "payments/drivers/mercadopago", form["data-driver"]
    assert_equal({ "public_key" => "APP_USR-chave-publica", "sdk_url" => "https://sdk.mercadopago.com/js/v2" }, JSON.parse(form["data-config"]))
    csp = csp_of(response)
    assert_includes csp["script-src"], "https://sdk.mercadopago.com"
    assert_includes csp["frame-src"], "https://secure-fields.mercadopago.com"
    csp.values.flatten.each { |source| assert_no_match(/\*|\Ahttp:/, source) }
  end

  test "pagar: o token, a bandeira e as parcelas vão ao Mercado Pago com o e-mail do pagador" do
    order = mercadopago_order(kind: "card", status: "processed", amount_cents: 100_000)
    client = use_mercadopago_client(mercadopago_client.on(:post, "/v1/orders", status: 201, body: order))
    post checkout_card_payment_path(@checkout), params: { payment_token: "ff8080814c11e237014c1ff593b57b4d", installments: 1, brand: "master" }
    assert_response :success
    body = JSON.parse(client.to("/v1/orders").sole.body)
    assert_equal({ "id" => "master", "type" => "credit_card", "token" => "ff8080814c11e237014c1ff593b57b4d", "installments" => 1 }, body.dig("transactions", "payments", 0, "payment_method"))
    assert_equal "maria@exemplo.com.br", body.dig("payer", "email")
    assert_nil body["config"], "sem 3DS (MPG5)"
    assert @checkout.reload.state_paid? || @checkout.state_card_approved?
  end

  test "recusa por dados do cartão volta com a mensagem e permite tentar de novo" do
    order = mercadopago_order(kind: "card", status: "failed", status_detail: "cc_rejected_bad_filled_security_code")
    use_mercadopago_client(mercadopago_client.on(:post, "/v1/orders", status: 201, body: order))
    post checkout_card_payment_path(@checkout), params: { payment_token: "ff8080814c11e237014c1ff593b57b4e", installments: 1, brand: "visa" }
    assert_response :success
    assert_select "form[data-cartao]"
  end
end
