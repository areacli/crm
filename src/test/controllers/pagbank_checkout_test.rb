require "test_helper"

# Página `/pagar` com cartão do PagBank (12, revisão 5, R284t a R284v): a política de conteúdo não libera domínio externo, o formulário leva o módulo do PagBank
# e a chave pública, o servidor recebe só o cartão cifrado, a bandeira e as parcelas, e a cobrança em análise mostra "em análise" sem nova tentativa.
class PagbankCheckoutTest < ActionDispatch::IntegrationTest
  ENCRYPTED = "#{'B' * 340}==".freeze

  setup do
    @alfa = tenants(:alfa)
    @customer = make_customer(@alfa)
    @account = make_pagbank_account(@alfa, modality: "card", environment: "production", expires_at: 30.days.from_now)
    @account.update!(config: @account.config.merge("card_public_key" => "MIIBIjANBgkq-CHAVE", "card_public_key_at" => Time.current.iso8601))
    @checkout = Payments::Checkouts.create(tenant: @alfa, customer: @customer, object: bill_for(@customer, amount_cents: 100_000), amount_cents: 100_000, card: true)
  end

  def order(status)
    { "id" => PagbankHttpHelper::ORDER_ID, "reference_id" => "REF", "charges" => [ { "id" => PagbankHttpHelper::CHARGE_ID, "status" => status, "payment_method" => { "installments" => 1 },
                                                                                        "amount" => { "value" => 100_000, "summary" => { "total" => 100_000, "paid" => (status == "PAID" ? 100_000 : 0) } } } ] }
  end

  test "a política de conteúdo só tem o nosso domínio; o formulário leva o módulo do PagBank, a chave pública e o SDK daqui (R284t)" do
    get checkout_path(@checkout)
    assert_response :success
    csp = csp_of(response)
    assert_equal [ "'self'" ], csp["script-src"].reject { |source| source.start_with?("'nonce-") }
    assert_equal [ "'self'", "ws://www.example.com" ], csp["connect-src"]
    assert_equal [ "'none'" ], csp["frame-src"]
    form = Nokogiri::HTML5(response.body).at_css("form[data-cartao]")
    assert_equal "payments/drivers/pagbank", form["data-driver"]
    assert_equal "", form["data-script"].to_s
    config = JSON.parse(form["data-config"])
    assert_equal "MIIBIjANBgkq-CHAVE", config["public_key"]
    assert_match %r{\A/assets/pagbank-checkout-sdk-}, config["sdk_url"]
    assert_select "#cartao-numero[name]", count: 0
    assert_select "input[type=hidden][name=brand]"
  end

  test "pagar: o servidor recebe o cartão cifrado e a bandeira; o dado de cartão enviado por engano nunca vai ao PagBank" do
    client = use_pagbank_client(pagbank_client.on(:post, "/orders", status: 201, body: order("PAID")))
    post checkout_card_payment_path(@checkout), params: { payment_token: ENCRYPTED, installments: 1, brand: "visa", number: "4111111111111111", cvv: "123" }
    assert_response :success
    sent = client.to("/orders").sole.body
    assert_includes sent, ENCRYPTED
    assert_not_includes sent, "4111111111111111"
    assert_not_includes sent, "\"123\""
    assert @checkout.reload.state_paid? || @checkout.state_card_approved?
  end

  test "cobrança em análise: \"em análise\", sem formulário para nova tentativa (R284u)" do
    use_pagbank_client(pagbank_client.on(:post, "/orders", status: 201, body: order("IN_ANALYSIS")))
    post checkout_card_payment_path(@checkout), params: { payment_token: ENCRYPTED, installments: 1, brand: "visa" }
    assert_response :success
    assert_includes response.body, "está em análise"
    assert_select "form[data-cartao]", count: 0
    assert @checkout.reload.state_card_approved?
  end

  test "sem a chave pública (o PagBank não respondeu), o link não oferece cartão agora, e a página abre" do
    @account.update!(config: @account.config.except("card_public_key", "card_public_key_at"))
    use_pagbank_client(pagbank_client.on(:post, "/public-keys", status: 503, body: {}))
    get checkout_path(@checkout)
    assert_response :success
    assert_select "form[data-cartao]", count: 0
  end
end
