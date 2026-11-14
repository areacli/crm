require "test_helper"

# Mercado Pago (12, revisão 6) com respostas gravadas a partir dos exemplos da documentação (14/11/2026): Pix e boleto pela API Orders com idempotência,
# vencimento de até 30 dias e o do fim de semana passado ao dia útil, e-mail do pagador exigido, ficha do boleto gerada aqui, boleto fora da página no
# vencimento, cancelamento pela API, lista de pagos com o identificador do aviso, conexão com a conta e a Public Key. Nenhum teste chama o Mercado Pago.
class PaymentsMercadopagoTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  ADDRESS = { street: "Rua das Flores", number: "10", district: "Centro", city: "Curitiba", state: "PR", zip: "80010-000" }.freeze

  setup do
    @alfa = tenants(:alfa)
    @mp = Payments::Providers::Mercadopago.new
  end

  def emit(kind, amount_cents: 125_000, due_on: Date.current + 10, email: true, address: true)
    bill = make_bill(@alfa, number: "NF-#{SecureRandom.hex(3)}", amount_cents: amount_cents)
    add_contact(bill.customer, "email", "maria@exemplo.com.br") if email && bill.customer.contacts.none? { |c| c.kind == "email" }
    add_address(bill.customer, ADDRESS) if address && bill.customer.contacts.none?(&:address?)
    Payments::Issuer.new.request(tenant: @alfa, kind: kind, amount_cents: amount_cents, customer: bill.customer, due_on: due_on, object: bill, environment: "sandbox")
  end

  test "manifesto: conexão por autorização, aviso por fornecedor, vencimento de até 30 dias, boleto sem pagamento depois do vencimento, cartão em campos do Mercado Pago" do
    capabilities = @mp.manifest.capabilities
    assert_equal [ "authorization", "provider", 30, false, true, "provider" ],
                 [ capabilities[:credentials], capabilities[:webhook], capabilities[:max_due_days], capabilities[:boleto_after_due], capabilities[:payer_email_required],
                   capabilities.dig(:card_checkout, :fields) ]
    assert_equal %w[boleto pix], capabilities[:repeatable_issue]
  end

  test "Pix: pedido na API Orders com idempotência, e-mail e documento do pagador, validade até o fim do vencimento; QR Code gerado aqui" do
    make_mercadopago_account(@alfa)
    client = use_mercadopago_client(mercadopago_client.on(:post, "/v1/orders", status: 201, body: mercadopago_order))
    instrument = emit("pix", due_on: Date.current + 2)
    perform_enqueued_jobs(only: IssueInstrumentJob)
    call = client.to("/v1/orders").sole
    body = JSON.parse(call.body)
    assert_equal "Bearer APP_USR-VENDEDOR", call.headers["Authorization"]
    assert_equal instrument.custom_id, call.headers["X-Idempotency-Key"]
    assert_equal [ "online", "automatic", "1250.00", instrument.custom_id ], body.values_at("type", "processing_mode", "total_amount", "external_reference")
    assert_equal({ "type" => "CPF", "number" => "52998224725" }, body.dig("payer", "identification"))
    assert_equal "maria@exemplo.com.br", body.dig("payer", "email")
    payment = body.dig("transactions", "payments", 0)
    assert_equal({ "id" => "pix", "type" => "bank_transfer" }, payment["payment_method"])
    assert_match(/\AP[12]DT\d+H\d+M\z/, payment["expiration_time"])
    instrument.reload
    assert_equal [ "active", MercadopagoHttpHelper::ORDER_ID ], [ instrument.state, instrument.external_id ]
    assert instrument.pix_qr_png.attached?, "a imagem é gerada aqui do copia e cola (o Mercado Pago dá JPEG)"
  end

  test "sem e-mail do pagador ou com vencimento além de 30 dias, falha sem chamada (R284y, R284ac)" do
    make_mercadopago_account(@alfa)
    client = use_mercadopago_client(mercadopago_client)
    bill = make_bill(@alfa, number: "NF-SEM-EMAIL", amount_cents: 1_000, document: PaymentsHelper::JOAO, name: "João")
    no_email = Payments::Issuer.new.request(tenant: @alfa, kind: "pix", amount_cents: 1_000, customer: bill.customer, due_on: Date.current + 5, object: bill, environment: "sandbox")
    Payments::Issuer.new.perform(no_email.reload)
    assert_match(/e-mail do pagador/, no_email.reload.failure_reason)
    far = emit("pix", due_on: Date.current + 31)
    Payments::Issuer.new.perform(far.reload)
    assert_match(/até 30 dias/, far.reload.failure_reason)
    assert_empty client.requests
  end

  test "boleto: endereço completo, vencimento do fim de semana passado ao dia útil pelo Mercado Pago, ficha gerada aqui e conferida (R284e, R284z)" do
    make_mercadopago_account(@alfa, modality: "boleto")
    saturday = (Date.current + 7).then { |date| date + ((6 - date.wday) % 7) }
    monday = saturday + 2
    order = mercadopago_order(kind: "boleto", line: mercadopago_line(monday, 125_000))
    client = use_mercadopago_client(mercadopago_client.on(:post, "/v1/orders", status: 201, body: order).on(:get, "/v1/orders/#{MercadopagoHttpHelper::ORDER_ID}", body: order))
    instrument = emit("boleto", due_on: saturday)
    perform_enqueued_jobs(only: IssueInstrumentJob)
    body = JSON.parse(client.to("/v1/orders").find { |request| request.method == "post" }.body)
    assert_equal({ "zip_code" => "80010000", "street_name" => "Rua das Flores", "street_number" => "10", "neighborhood" => "Centro", "city" => "Curitiba", "state" => "PR" },
                 body.dig("payer", "address"))
    assert_equal "P#{(saturday - Date.current).to_i}D", body.dig("transactions", "payments", 0, "expiration_time")
    instrument.reload
    assert_equal "active", instrument.state, instrument.failure_reason
    assert_equal monday, instrument.due_on
    assert_equal saturday.iso8601, instrument.response_summary["requested_due_on"]
    assert instrument.boleto_pdf.attached?
    assert instrument.boleto_pdf.download.start_with?("%PDF")
  end

  test "boleto cuja linha não fecha com o valor falha sem PDF" do
    make_mercadopago_account(@alfa, modality: "boleto")
    order = mercadopago_order(kind: "boleto", line: mercadopago_line(Date.current + 10, 999))
    use_mercadopago_client(mercadopago_client.on(:post, "/v1/orders", status: 201, body: order).on(:get, "/v1/orders/", body: order))
    instrument = emit("boleto")
    Payments::Issuer.new.perform(instrument.reload)
    assert_equal "failed", instrument.reload.state
    assert_match(/ficha de compensação não foi gerada/, instrument.failure_reason)
  end

  test "o boleto do Mercado Pago sai da página do cliente no dia seguinte ao vencimento (R284aa)" do
    account = make_mercadopago_account(@alfa, modality: "boleto")
    instrument = PaymentInstrument.new(account: account, due_on: Date.current - 1)
    checkout = PaymentCheckout.new
    assert_equal Date.current - 1, checkout.boleto_payable_until(instrument)
    assert_not checkout.boleto_payable?(instrument)
  end

  test "consulta, cancelamento pela API com idempotência, vencimento recusado e devolução pela transação" do
    account = make_mercadopago_account(@alfa)
    use_mercadopago_client(mercadopago_client.on(:get, "/v1/orders/", body: mercadopago_order(status: "processed")))
    paid = @mp.fetch_pix(account, MercadopagoHttpHelper::ORDER_ID)
    assert_equal [ "paid", 125_000 ], [ paid.status, paid.paid_cents ]
    use_mercadopago_client(mercadopago_client.on(:get, "/v1/orders/", body: mercadopago_order(status: "refunded", refunds: [ { "id" => "REF1", "amount" => "300.00" } ])))
    assert_equal [ "paid", 30_000 ], @mp.fetch_pix(account, MercadopagoHttpHelper::ORDER_ID).then { |issued| [ issued.status, issued.refunded_cents ] }
    client = use_mercadopago_client(mercadopago_client.on(:post, "/cancel", body: mercadopago_order(status: "canceled")))
    assert_equal "canceled", @mp.cancel_pix(account, MercadopagoHttpHelper::ORDER_ID).status
    assert_equal "cancel-#{MercadopagoHttpHelper::ORDER_ID}", client.to("/cancel").sole.headers["X-Idempotency-Key"]
    assert_raises(Payments::Providers::Base::NotAvailable) { @mp.change_boleto_due_date(account, MercadopagoHttpHelper::ORDER_ID, Date.current + 5) }
    client = use_mercadopago_client(mercadopago_client.on(:get, "/v1/orders/", body: mercadopago_order(status: "processed")).on(:post, "/refund", body: {}))
    @mp.refund_pix(account, MercadopagoHttpHelper::ORDER_ID, amount_cents: 30_000)
    assert_equal({ "transactions" => [ { "id" => MercadopagoHttpHelper::PAYMENT_ID, "amount" => "300.00" } ] }, JSON.parse(client.to("/refund").sole.body))
  end

  test "lista de pagos: os pedidos pagos do meio da integração, com o mesmo identificador do aviso (R284b, R284c)" do
    account = make_mercadopago_account(@alfa)
    pix = mercadopago_order(status: "processed")
    card = mercadopago_order(kind: "card", status: "processed").merge("id" => "ORD-CARTAO")
    client = use_mercadopago_client(mercadopago_client.on(:get, "/v1/orders?", body: { "data" => [ pix, card ] }))
    notifications = @mp.list_paid(account, from: 1.hour.ago, to: Time.current)
    assert_equal [ "#{MercadopagoHttpHelper::ORDER_ID}:processed" ], notifications.map(&:event_id)
    query = Rack::Utils.parse_query(URI.parse(client.requests.sole.url).query)
    assert_equal [ "processed", "1", "100" ], query.values_at("status", "page", "page_size")
    _account, from_webhook = @mp.parse_provider_notification(body: { "type" => "order", "action" => "order.processed", "data" => { "id" => MercadopagoHttpHelper::ORDER_ID },
                                                                      "user_id" => MercadopagoHttpHelper::SELLER, "live_mode" => false }.to_json,
                                                              headers: mercadopago_signature(MercadopagoHttpHelper::ORDER_ID, secret: "segredo-webhook-sandbox"), context: {}) if with_mercadopago_app
    assert_equal notifications.first.event_id, from_webhook.first.event_id
  end

  test "conexão: a troca do código guarda a conta conectada e a Public Key, e pede credencial de teste no ambiente de homologação (R284x)" do
    with_mercadopago_app
    account = make_mercadopago_account(@alfa, connected: false)
    client = use_mercadopago_client(mercadopago_client.on(:post, "/oauth/token", body: { "access_token" => "APP_USR-NOVO", "refresh_token" => "TG-NOVO", "expires_in" => 15_552_000,
                                                                                            "user_id" => 123_456_789, "public_key" => "APP_USR-publica-nova" }))
    session = { Payments::Connection::SESSION_KEY => { "state" => "s" * 43, "account_id" => account.id, "user_id" => users(:joana).id, "expires_at" => 5.minutes.from_now.to_i } }
    previous = Rails.configuration.x.payments.public_url
    Rails.configuration.x.payments.public_url = "https://crm.exemplo.com.br"
    Payments::Connection.new(users(:joana)).finish(session, state: "s" * 43, code: "TG-CODIGO")
    account.reload
    assert_equal [ "123456789", "APP_USR-publica-nova" ], account.config.values_at("connection_account_id", "connection_public_key")
    body = JSON.parse(client.to("/oauth/token").sole.body)
    assert_equal [ "authorization_code", "TG-CODIGO", true, "app-mp-sandbox" ], body.values_at("grant_type", "code", "test_token", "client_id")
    url = @mp.authorization_url(account, app: Payments::Connection.app("mercadopago", "sandbox"), state: "abc", redirect_uri: "https://crm.exemplo.com.br/r")
    assert_equal [ "auth.mercadopago.com", "app-mp-sandbox", "mp", "code" ], [ URI.parse(url).host, *Rack::Utils.parse_query(URI.parse(url).query).values_at("client_id", "platform_id", "response_type") ]
  ensure
    Rails.configuration.x.payments.public_url = previous
  end
  test "cartão: parcelas pela bandeira, sem o BIN; em processamento fica em análise; recusa pela classificação do status_detail" do
    account = make_mercadopago_account(@alfa, modality: "card")
    costs = [ { "payment_method_id" => "visa", "payer_costs" => [ { "installments" => 1, "installment_rate" => 0, "installment_amount" => 1000, "total_amount" => 1000 },
                                                                  { "installments" => 6, "installment_rate" => 9.89, "installment_amount" => 182.97, "total_amount" => 1097.82 } ] } ]
    client = use_mercadopago_client(mercadopago_client.on(:get, "/v1/payment_methods/installments", body: costs))
    options = @mp.installments(account, amount_cents: 100_000, brand: "visa")
    assert_equal [ [ 1, false ], [ 6, true ] ], options.map { |option| [ option.installments, option.has_interest ] }
    assert_equal({ "amount" => "1000.00", "payment_method_id" => "visa" }, Rack::Utils.parse_query(URI.parse(client.requests.sole.url).query))
    payer = { name: "Maria Souza", document: "52998224725", email: "maria@exemplo.com.br" }
    use_mercadopago_client(mercadopago_client.on(:post, "/v1/orders", status: 201, body: mercadopago_order(kind: "card", status: "processing")))
    assert_equal "in_analysis", @mp.charge_card(account, custom_id: "K" * 32, amount_cents: 100_000, installments: 1, payment_token: "tok", payer: payer, brand: "visa").status
    use_mercadopago_client(mercadopago_client.on(:post, "/v1/orders", status: 201, body: mercadopago_order(kind: "card", status: "failed", status_detail: "cc_rejected_high_risk")))
    result = @mp.charge_card(account, custom_id: "K" * 32, amount_cents: 100_000, installments: 1, payment_token: "tok", payer: payer, brand: "visa")
    assert_equal [ "declined", "security", false ], [ result.status, result.refusal_code, result.retry ]
    assert_raises(Payments::Providers::Error) { @mp.charge_card(account, custom_id: "K" * 32, amount_cents: 100_000, installments: 1, payment_token: "tok", payer: payer.merge(email: nil), brand: "visa") }
  end
end
