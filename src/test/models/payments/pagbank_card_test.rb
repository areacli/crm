require "test_helper"

# Cartão do PagBank (12, revisão 5, R284t a R284v): o SDK cifra o cartão no navegador e o servidor recebe só o cartão cifrado, que não consegue abrir; parcelas
# pela API de taxas por bandeira, juros do comprador fora do pagamento, estado em análise, recusas pela tabela do PagBank e o SDK conferido pelo SHA-256.
class PaymentsPagbankCardTest < ActiveSupport::TestCase
  ENCRYPTED = "#{'A' * 340}==".freeze

  setup do
    @alfa = tenants(:alfa)
    @pagbank = Payments::Providers::Pagbank.new
    @account = make_pagbank_account(@alfa, modality: "card")
    @payer = { name: "Maria Souza", document: "52998224725", email: "maria@exemplo.com.br" }
  end

  def card_order(status, paid: nil, interest: 0, code: nil)
    order = pagbank_order(kind: "card", status: status, paid: paid, amount: 100_000 + interest)
    charge = order["charges"].first
    charge["payment_method"] = { "type" => "CREDIT_CARD", "installments" => 6 }
    charge["amount"]["fees"] = { "buyer" => { "interest" => { "total" => interest, "installments" => 6 } } } if interest.positive?
    charge["payment_response"] = { "code" => code, "message" => "NAO AUTORIZADA" } if code
    order
  end

  def fees_response
    { "payment_methods" => { "credit_card" => { "visa" => { "installment_plans" => [
      { "installments" => 1, "installment_value" => 100_000, "interest_free" => true, "amount" => { "value" => 100_000 } },
      { "installments" => 3, "installment_value" => 33_334, "interest_free" => true, "amount" => { "value" => 100_000 } },
      { "installments" => 6, "installment_value" => 18_157, "interest_free" => false, "amount" => { "value" => 108_942 } }
    ] } } } }
  end

  def charge(installments: 1, brand: "visa")
    @pagbank.charge_card(@account, custom_id: "K" * 32, amount_cents: 100_000, installments: installments, payment_token: ENCRYPTED, payer: @payer, description: "Mensalidade",
                                   notification_url: "https://crm.exemplo.com.br/webhooks/pagamentos/contas/1?hmac=#{'a' * 32}", brand: brand)
  end

  test "só o cartão cifrado vai ao PagBank, com store falso, captura e o nome na fatura sem acento (R284t)" do
    client = use_pagbank_client(pagbank_client.on(:post, "/orders", status: 201, body: card_order("PAID", paid: 100_000)))
    result = charge
    body = JSON.parse(client.to("/orders").sole.body)
    method = body.dig("charges", 0, "payment_method")
    assert_equal({ "encrypted" => ENCRYPTED, "store" => false }, method["card"])
    assert_equal [ "CREDIT_CARD", 1, true, "Escola Alfa" ], method.values_at("type", "installments", "capture", "soft_descriptor")
    assert_equal({ "name" => "Maria Souza", "tax_id" => "52998224725" }, method["holder"])
    assert_equal 100_000, body.dig("charges", 0, "amount", "value")
    assert_nil body.dig("charges", 0, "amount", "fees")
    assert_equal [ "paid", PagbankHttpHelper::ORDER_ID, 100_000 ], [ result.status, result.external_id, result.amount_cents ]
  end

  test "acima das parcelas sem juros, o total com juros vem da API de taxas pela bandeira, e o pagamento entra pelo valor do instrumento (R284v)" do
    client = use_pagbank_client(pagbank_client.on(:get, "/charges/fees/calculate", body: fees_response).on(:post, "/orders", status: 201, body: card_order("PAID", paid: 108_942, interest: 8_942)))
    result = charge(installments: 6)
    fees_query = Rack::Utils.parse_query(URI.parse(client.to("/charges/fees/calculate").sole.url).query)
    assert_equal({ "payment_methods" => "CREDIT_CARD", "value" => "100000", "max_installments" => "6", "max_installments_no_interest" => "3" }, fees_query)
    amount = JSON.parse(client.to("/orders").sole.body).dig("charges", 0, "amount")
    assert_equal 108_942, amount["value"]
    assert_equal({ "total" => 8_942, "installments" => 6 }, amount.dig("fees", "buyer", "interest"))
    assert_equal 100_000, result.amount_cents, "os juros são da operadora"
    use_pagbank_client(pagbank_client.on(:get, "/orders/", body: card_order("PAID", paid: 108_942, interest: 8_942)))
    fetched = @pagbank.fetch_card(@account, PagbankHttpHelper::ORDER_ID)
    assert_equal [ "paid", 100_000, 100_000 ], [ fetched.status, fetched.amount_cents, fetched.paid_cents ]
  end

  test "parcelado com juros sem bandeira, ou sem o plano na resposta, não cobra" do
    client = use_pagbank_client(pagbank_client.on(:get, "/charges/fees/calculate", body: { "payment_methods" => {} }))
    assert_raises(Payments::Providers::Error) { charge(installments: 6, brand: nil) }
    assert_raises(Payments::Providers::Error) { charge(installments: 6) }
    assert_empty client.to("/orders")
  end

  test "parcelas da página: as da bandeira, limitadas ao máximo da integração; sem bandeira, à vista" do
    use_pagbank_client(pagbank_client.on(:get, "/charges/fees/calculate", body: fees_response))
    options = @pagbank.installments(@account, amount_cents: 100_000, brand: "visa")
    assert_equal [ 1, 3, 6 ], options.map(&:installments)
    assert_equal [ false, false, true ], options.map(&:has_interest)
    assert_equal [ 1 ], @pagbank.installments(@account, amount_cents: 100_000).map(&:installments)
  end

  test "em análise, autorizado e recusas pela tabela do PagBank (R284u)" do
    use_pagbank_client(pagbank_client.on(:post, "/orders", status: 201, body: card_order("IN_ANALYSIS")))
    assert_equal "in_analysis", charge.status
    use_pagbank_client(pagbank_client.on(:post, "/orders", status: 201, body: card_order("AUTHORIZED")))
    assert_equal "approved", charge.status
    { "20007" => [ "invalid_data", false ], "10000" => [ "security", true ], "10002" => [ "try_later", true ], "20003" => [ "other", true ], "10001" => [ "other", false ] }.each do |code, (ours, retry_flag)|
      use_pagbank_client(pagbank_client.on(:post, "/orders", status: 201, body: card_order("DECLINED", code: code)))
      result = charge
      assert_equal [ "declined", ours, retry_flag ], [ result.status, result.refusal_code, result.retry ], code
    end
  end

  test "a chave pública é pedida uma vez, guardada na integração e renovada depois de um ano; a página recebe o SDK do nosso domínio com integridade" do
    client = use_pagbank_client(pagbank_client.on(:post, "/public-keys", body: { "public_key" => "MIIBIjANBgkq-CHAVE", "created_at" => 1_700_000_000 }))
    config = @pagbank.card_checkout_config(@account)
    assert_equal "MIIBIjANBgkq-CHAVE", config["public_key"]
    assert_match(%r{\A/assets/pagbank-checkout-sdk-\h+\.js\z}, config["sdk_url"])
    assert_equal "sha256-#{[ [ Payments::Providers::Pagbank::SDK_SHA256 ].pack('H*') ].pack('m0')}", config["sdk_integrity"]
    @pagbank.card_checkout_config(@account.reload)
    assert_equal({ "type" => "card" }, JSON.parse(client.to("/public-keys").sole.body))
    @account.update!(config: @account.reload.config.except("token_expires_at"))
    travel(366.days) { @pagbank.card_checkout_config(@account.reload) }
    assert_equal 2, client.to("/public-keys").size
    assert_equal({ script: [], connect: [], frame: [], img: [] }, @pagbank.card_checkout_hosts(@account))
  end

  test "o SDK servido é o do SHA-256 do adaptador (fica fora do repositório público: sem o arquivo, o teste diz como baixar)" do
    path = Rails.root.join("vendor/javascript", Payments::Providers::Pagbank::SDK_FILE)
    skip "SDK do PagBank fora do repositório público: rode crm:payments:card_sdk[pagbank]" unless path.exist?
    assert_equal Payments::Providers::Pagbank::SDK_SHA256, Digest::SHA256.file(path).hexdigest
    assert_equal Payments::Providers::Pagbank::SDK_SHA256, @pagbank.manifest.capabilities.dig(:card_checkout, :sdk_sha256)
  end

  test "reembolso pela cobrança do pedido" do
    client = use_pagbank_client(pagbank_client.on(:get, "/orders/", body: card_order("PAID", paid: 100_000)).on(:post, "/charges/#{PagbankHttpHelper::CHARGE_ID}/cancel", body: {}))
    @pagbank.refund_card(@account, PagbankHttpHelper::ORDER_ID, amount_cents: 30_000)
    assert_equal({ "amount" => { "value" => 30_000 } }, JSON.parse(client.to("/cancel").sole.body))
  end
end
