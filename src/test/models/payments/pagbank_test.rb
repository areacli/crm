require "test_helper"

# PagBank (12, revisão 5) com respostas gravadas a partir dos exemplos do portal (14/11/2026): Pix com validade até o fim do vencimento, boleto com PDF baixado
# do domínio de boletos e endereço completo, sem repetição depois de tempo esgotado, cancelamento só aqui, sem troca de vencimento, aviso com o pedido inteiro
# autenticado pela chave da URL e o formato antigo "para conferir". Nenhum teste chama o PagBank.
class PaymentsPagbankTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  ADDRESS = { street: "Rua das Flores", number: "10", complement: "apto 3", district: "Centro", city: "Curitiba", state: "PR", zip: "80010-000" }.freeze

  setup do
    @alfa = tenants(:alfa)
    @pagbank = Payments::Providers::Pagbank.new
    @payer = { name: "Maria Souza", document: "529.982.247-25", address: ADDRESS.transform_keys(&:to_s) }
  end

  def emit(kind, amount_cents: 125_000, due_on: Date.new(2026, 11, 30), with_address: true, environment: "sandbox")
    bill = make_bill(@alfa, number: "NF-#{SecureRandom.hex(3)}", amount_cents: amount_cents)
    add_address(bill.customer, ADDRESS) if with_address && bill.customer.contacts.none?(&:address?)
    Payments::Issuer.new.request(tenant: @alfa, kind: kind, amount_cents: amount_cents, customer: bill.customer, due_on: due_on, object: bill, environment: environment)
  end

  test "manifesto: sem campo de credencial, chave da URL, cancelamento só aqui, sem troca de vencimento, Pix com validade, conciliação diária (R284k a R284r)" do
    manifest = @pagbank.manifest
    assert_equal %w[boleto pix card], manifest.modalities
    assert_equal "authorization", manifest.capabilities[:credentials]
    assert_equal "per_charge", manifest.capabilities[:webhook_url]
    assert_equal [], manifest.capabilities[:repeatable_issue]
    assert_equal({ "boleto" => "local", "pix" => "local" }, manifest.capabilities[:cancel])
    assert_equal false, manifest.capabilities[:due_date_change]
    assert_equal 1, manifest.capabilities[:reconcile_after_days]
    assert_empty manifest.fields_for("pix").reject(&:generated).select { |field| field.name.in?(%w[fine_percent interest_percent discount_percent]) }, "Pix sem multa nem juros (R284q)"
    assert_empty manifest.fields.select(&:secret?).reject(&:generated), "nenhum segredo digitado: a credencial vem da conexão"
  end

  test "a integração nasce com a chave da URL, e a URL do aviso não muda quando o segredo do webhook troca (R284m)" do
    with_config(public_url: "https://crm.exemplo.com.br") do
      account = make_pagbank_account(@alfa, modality: "boleto")
      assert account.secrets["webhook_url_key"].present?
      url = Payments::WebhookUrl.for(account)
      assert_match %r{\Ahttps://crm\.exemplo\.com\.br/webhooks/pagamentos/contas/#{account.id}\?hmac=\h{32}\z}, url
      account.rotate_webhook_secret!
      account.rotate_webhook_secret!
      assert_equal url, Payments::WebhookUrl.for(account.reload)
      assert Payments::WebhookUrl.valid?(account, url[/hmac=(\h+)/, 1])
    end
  end

  test "Pix: pedido com qr_codes, validade até 23h59 do vencimento, sem multa, com o token da conexão, o identificador e a URL do aviso (R284q)" do
    with_config(public_url: "https://crm.exemplo.com.br") do
      account = make_pagbank_account(@alfa)
      client = use_pagbank_client(pagbank_client.on(:post, "/orders", status: 201, body: pagbank_order))
      instrument = emit("pix")
      perform_enqueued_jobs(only: IssueInstrumentJob)
      instrument.reload
      call = client.to("/orders").first
      body = JSON.parse(call.body)
      assert_equal "https://sandbox.api.pagseguro.com/orders", call.url
      assert_equal "Bearer TOKEN-VENDEDOR-1", call.headers["Authorization"]
      assert_equal instrument.custom_id, call.headers["x-idempotency-key"]
      assert_equal [ { "amount" => { "value" => 125_000 }, "expiration_date" => "2026-11-30T23:59:59-03:00" } ], body["qr_codes"]
      assert_equal "52998224725", body.dig("customer", "tax_id")
      assert_equal [ Payments::WebhookUrl.for(account) ], body["notification_urls"]
      assert_nil body["charges"]
      assert_equal "active", instrument.state
      assert_equal PagbankHttpHelper::ORDER_ID, instrument.external_id
      assert_match(/\A000201/, instrument.copy_paste)
      assert instrument.pix_qr_png.attached?, "QR Code gerado aqui (PB13)"
      assert_empty client.requests.select { |request| request.url.include?("qrcode") }, "o PNG do PagBank não é baixado"
    end
  end

  test "Pix sem idempotência documentada: tempo esgotado na leitura falha com motivo e não repete (R284n)" do
    make_pagbank_account(@alfa)
    client = use_pagbank_client(pagbank_client.on(:post, "/orders") { raise Payments::Providers::NetworkError.new("o fornecedor não respondeu a tempo", retry_safe: false) })
    instrument = emit("pix")
    Payments::Issuer.new.perform(instrument.reload)
    assert_equal "failed", instrument.reload.state
    assert_match(/não respondeu a tempo/, instrument.failure_reason)
    assert_equal 1, client.to("/orders").size
  end

  test "excesso de requisições (40004 com HTTP 400) é indisponibilidade que se repete, não recusa" do
    make_pagbank_account(@alfa)
    use_pagbank_client(pagbank_client.on(:post, "/orders", status: 400, body: { "error_messages" => [ { "code" => "40004", "description" => "rate_limit" } ] }))
    instrument = emit("pix")
    error = assert_raises(Payments::Providers::NetworkError) { Payments::Issuer.new.perform(instrument.reload) }
    assert error.retry_safe
    assert_equal "emitting", instrument.reload.state
  end

  test "Pix recusado pela análise de risco falha com motivo" do
    make_pagbank_account(@alfa)
    use_pagbank_client(pagbank_client.on(:post, "/orders", status: 201, body: pagbank_order(status: "DECLINED")))
    instrument = emit("pix")
    Payments::Issuer.new.perform(instrument.reload)
    assert_equal "failed", instrument.reload.state
    assert_match(/análise de risco/, instrument.failure_reason)
  end

  test "boleto: modelo cobrança com percentuais vezes 100, endereço completo, instruções em duas linhas e PDF baixado do domínio de boletos (R273)" do
    make_pagbank_account(@alfa, modality: "boleto")
    order = pagbank_order(kind: "boleto", status: "WAITING")
    client = use_pagbank_client(pagbank_client.on(:post, "/orders", status: 201, body: order).on(:get, "/orders/#{PagbankHttpHelper::ORDER_ID}", body: order)
                                              .on(:get, "boleto.pagseguro.com.br/BOLE_1.pdf", raw: Payments::Providers::Fake::PDF))
    instrument = emit("boleto")
    perform_enqueued_jobs(only: IssueInstrumentJob)
    instrument.reload
    body = JSON.parse(client.to("/orders").first.body)
    charge = body["charges"].first
    boleto = charge.dig("payment_method", "boleto")
    assert_equal "cobranca", boleto["template"]
    assert_equal "2026-11-30", boleto["due_date"]
    assert_equal "30", boleto["days_until_expiration"]
    assert_equal({ "street" => "Rua das Flores", "number" => "10", "complement" => "apto 3", "locality" => "Centro", "city" => "Curitiba", "region" => "Paraná",
                   "region_code" => "PR", "country" => "BRA", "postal_code" => "80010000" }, boleto.dig("holder", "address"))
    assert_equal({ "date" => "2026-12-01", "value" => 200 }, charge.dig("payment_instructions", "fine"))
    assert_equal({ "date" => "2026-12-01", "value" => 100 }, charge.dig("payment_instructions", "interest"))
    assert boleto.dig("instruction_lines", "line_1").length <= 75
    assert_equal "active", instrument.state
    assert_equal "03399.85301 29700.000242 27020.901016 2 78150000125000", instrument.digitable_line
    assert instrument.boleto_pdf.attached?
    pdf = client.to("BOLE_1.pdf").first
    assert_nil pdf.headers["Authorization"], "o PDF se baixa sem credencial nossa"
  end

  test "boleto sem endereço completo do pagador falha sem chamar o PagBank (R274, PB11)" do
    make_pagbank_account(@alfa, modality: "boleto")
    client = use_pagbank_client(pagbank_client)
    instrument = emit("boleto", with_address: false)
    Payments::Issuer.new.perform(instrument.reload)
    assert_equal "failed", instrument.reload.state
    assert_match(/endereço completo/, instrument.failure_reason)
    assert_empty client.requests
  end

  test "boleto abaixo de R$ 0,20 falha sem chamada; PDF de outro domínio é recusado" do
    make_pagbank_account(@alfa, modality: "boleto")
    client = use_pagbank_client(pagbank_client)
    small = emit("boleto", amount_cents: 19)
    Payments::Issuer.new.perform(small.reload)
    assert_match(/mínimo/, small.reload.failure_reason)
    assert_empty client.requests

    order = pagbank_order(kind: "boleto", status: "WAITING", extra_charge: { "links" => [ { "href" => "https://outro.exemplo.com/BOLE_1.pdf", "media" => "application/pdf" } ] })
    order["charges"].first["links"] = [ { "href" => "https://outro.exemplo.com/BOLE_1.pdf", "media" => "application/pdf" } ]
    use_pagbank_client(pagbank_client.on(:post, "/orders", status: 201, body: order).on(:get, "/orders/", body: order))
    instrument = emit("boleto")
    Payments::Issuer.new.perform(instrument.reload)
    assert_equal "failed", instrument.reload.state
    assert_match(/não é o de boletos do PagBank/, instrument.failure_reason)
  end

  test "consulta: pago com valor e devolução, não pago na validade vence" do
    account = make_pagbank_account(@alfa)
    use_pagbank_client(pagbank_client.on(:get, "/orders/", body: pagbank_order(status: "PAID", paid: 125_000)))
    paid = @pagbank.fetch_pix(account, PagbankHttpHelper::ORDER_ID)
    assert_equal [ "paid", 125_000, 0 ], [ paid.status, paid.paid_cents, paid.refunded_cents ]
    use_pagbank_client(pagbank_client.on(:get, "/orders/", body: pagbank_order(status: "CANCELED")))
    assert_equal "expired", @pagbank.fetch_pix(account, PagbankHttpHelper::ORDER_ID).status
    use_pagbank_client(pagbank_client.on(:get, "/orders/", body: pagbank_order(kind: "boleto", status: "WAITING")))
    assert_equal "active", @pagbank.fetch_boleto(account, PagbankHttpHelper::ORDER_ID).status
  end

  test "cancelar é só aqui, o instrumento segue pagável no PagBank e o pagamento que vier entra; a conferência para quando ele vence (R284o)" do
    account = make_pagbank_account(@alfa, expires_at: 30.days.from_now)
    use_pagbank_client(pagbank_client.on(:post, "/orders", status: 201, body: pagbank_order))
    instrument = emit("pix")
    Payments::Issuer.new.perform(instrument.reload)
    client = use_pagbank_client(pagbank_client)
    Payments::Issuer.new.cancel(instrument.reload)
    assert_equal "canceled", instrument.reload.state
    assert instrument.response_summary["canceled_locally_at"].present?
    assert_empty client.requests, "sem chamada de cancelamento"

    travel 2.days do
      assert_includes Payments::Reconciler.new(@alfa).due.to_a, instrument
      use_pagbank_client(pagbank_client.on(:get, "/orders/", body: pagbank_order(status: "PAID", paid: 125_000)))
      outcome = Payments::InstrumentSync.new.call(instrument.reload)
      assert_equal "paid", instrument.reload.state, outcome.text
      assert instrument.payment.present?
    end

    other = emit("pix")
    use_pagbank_client(pagbank_client.on(:post, "/orders", status: 201, body: pagbank_order.merge("id" => "ORDE_OUTRO")))
    Payments::Issuer.new.perform(other.reload)
    Payments::Issuer.new.cancel(other.reload)
    use_pagbank_client(pagbank_client.on(:get, "/orders/", body: pagbank_order(status: "CANCELED").merge("id" => "ORDE_OUTRO")))
    Payments::InstrumentSync.new.call(other.reload)
    assert_equal "canceled", other.reload.state
    assert other.response_summary["canceled_locally_closed_at"].present?
    travel(2.days) { assert_not_includes Payments::Reconciler.new(@alfa).due.to_a, other }
    assert account
  end

  test "mudar o vencimento é recusado sem chamada (R284p)" do
    make_pagbank_account(@alfa, modality: "boleto")
    order = pagbank_order(kind: "boleto", status: "WAITING")
    use_pagbank_client(pagbank_client.on(:post, "/orders", status: 201, body: order).on(:get, "/orders/", body: order).on(:get, "BOLE_1.pdf", raw: Payments::Providers::Fake::PDF))
    instrument = emit("boleto", due_on: Date.current + 10)
    Payments::Issuer.new.perform(instrument.reload)
    client = use_pagbank_client(pagbank_client)
    error = assert_raises(Payments::Issuer::Refused) { Payments::Issuer.new.change_due_date(instrument.reload, Date.current + 20) }
    assert_match(/não muda o vencimento/, error.message)
    assert_empty client.requests
  end

  test "conciliação: o ativo do PagBank é conferido depois de 1 dia; o do falso, depois de 3 (R284r)" do
    make_pagbank_account(@alfa)
    use_pagbank_client(pagbank_client.on(:post, "/orders", status: 201, body: pagbank_order))
    pagbank = emit("pix")
    Payments::Issuer.new.perform(pagbank.reload)
    fake = emit_fake_pix
    travel 25.hours do
      due = Payments::Reconciler.new(@alfa).due.to_a
      assert_includes due, pagbank.reload
      assert_not_includes due, fake
    end
    travel(73.hours) { assert_includes Payments::Reconciler.new(@alfa).due.to_a, fake }
  end

  test "aviso: o pedido inteiro com o hmac da chave da URL vira um aviso; o mesmo estado repetido é o mesmo evento; hmac errado é recusado" do
    with_config(public_url: "https://crm.exemplo.com.br") do
      account = make_pagbank_account(@alfa)
      hmac = Payments::WebhookUrl.for(account)[/hmac=(\h+)/, 1]
      body = pagbank_order(status: "PAID", paid: 125_000, reference: "REF-1").to_json
      first = @pagbank.parse_notification(account, body: body, headers: {}, context: { query: { "hmac" => hmac } })
      second = @pagbank.parse_notification(account, body: body, headers: {}, context: { query: { "hmac" => hmac } })
      assert_equal 1, first.size
      notification = first.first
      assert_equal :paid, notification.kind
      assert_equal PagbankHttpHelper::ORDER_ID, notification.external_id
      assert_equal 125_000, notification.amount_cents
      assert_equal "E18236120202611141005s0123456789", notification.end_to_end_id
      assert_equal "REF-1", notification.custom_id
      assert_equal notification.event_id, second.first.event_id
      changed = @pagbank.parse_notification(account, body: pagbank_order(status: "PAID", paid: 125_000, refunded: 30_000).to_json, headers: {}, context: { query: { "hmac" => hmac } })
      assert_not_equal notification.event_id, changed.first.event_id
      assert_equal :refunded, changed.first.kind
      assert_raises(Payments::Providers::InvalidSignature) { @pagbank.parse_notification(account, body: body, headers: {}, context: { query: { "hmac" => "0" * 32 } }) }
      assert_equal [], @pagbank.parse_notification(account, body: "{}", headers: {}, context: {})
    end
  end

  test "aviso no formato antigo vai a \"para conferir\" sem consulta (R284s)" do
    with_config(public_url: "https://crm.exemplo.com.br") do
      account = make_pagbank_account(@alfa)
      hmac = Payments::WebhookUrl.for(account)[/hmac=(\h+)/, 1]
      notifications = @pagbank.parse_notification(account, body: "notificationCode=766B9C-AD4B044B04DA-77742F5FA653-E1AB24&notificationType=transaction", headers: {}, context: { query: { "hmac" => hmac } })
      assert_equal :unreadable, notifications.first.kind
      event, queue = PaymentEvent.record(account, notifications.first)
      assert queue
      client = use_pagbank_client(pagbank_client)
      Payments::EventProcessor.new.run(event)
      assert_equal "review", event.reload.state
      assert_empty client.requests
    end
  end

  test "teste de conexão: sem conexão diz que não está conectada; conectada, o pedido inexistente (404) prova o token" do
    account = make_pagbank_account(@alfa, connected: false)
    assert_equal false, @pagbank.test_connection(account).ok
    account.update!(secrets: account.secrets.merge("access_token" => "TOKEN-VENDEDOR-1"), config: account.config.merge("connection_state" => "connected"))
    use_pagbank_client(pagbank_client.on(:get, "/orders/#{Payments::Providers::Pagbank::PROBE_ORDER}", status: 404, body: { "error_messages" => [ { "code" => "40401" } ] }))
    assert @pagbank.test_connection(account).ok?
    use_pagbank_client(pagbank_client.on(:get, "/orders/", status: 403, body: { "error_messages" => [ { "code" => "ACCESS_DENIED", "description" => "whitelist" } ] }))
    assert_equal false, @pagbank.test_connection(account).ok
  end

  test "integração desconectada: a emissão falha com motivo e nada sai" do
    make_pagbank_account(@alfa, connected: false)
    client = use_pagbank_client(pagbank_client)
    instrument = emit("pix")
    Payments::Issuer.new.perform(instrument.reload)
    assert_equal "failed", instrument.reload.state
    assert_match(/desconectada/, instrument.failure_reason)
    assert_empty client.requests
  end

  private
    def emit_fake_pix
      make_account(@alfa, modality: "pix", environment: "production", config: { "connection_result" => "ok", "pix_key" => "p@a.com" }, nickname: "falso pix")
      bill = make_bill(@alfa, number: "NF-FAKE-#{SecureRandom.hex(2)}", amount_cents: 1_000)
      instrument = Payments::Issuer.new.request(tenant: @alfa, kind: "pix", amount_cents: 1_000, customer: bill.customer, due_on: Date.current + 10, object: bill, environment: "production")
      Payments::Issuer.new.perform(instrument.reload)
      instrument.reload
    end

    def with_config(public_url:)
      previous = Rails.configuration.x.payments.public_url
      Rails.configuration.x.payments.public_url = public_url
      yield
    ensure
      Rails.configuration.x.payments.public_url = previous
    end
end
