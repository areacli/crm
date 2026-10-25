require "test_helper"

# Avisos da Efí (12, parte D, R281 a R283) com corpos gravados à mão a partir da documentação (notificações de cobranças e webhook do Pix): leitura e
# autenticação sem chamar a Efí, token trocado pela lista de mudanças, consulta de pago e devolvido. Nenhum teste chama a Efí real.
class PaymentsEfiWebhookTest < ActiveSupport::TestCase
  EFI_IP = "34.193.116.226".freeze
  TXID = "T" * 32

  setup do
    @alfa = tenants(:alfa)
    @efi = Payments::Providers::Efi.new
    @account = make_efi_account(@alfa, modality: "pix")
    @secret = @account.rotate_webhook_secret!
    @hmac = Payments::WebhookUrl.token(@account, @secret)
  end

  PIX_BODY = { "pix" => [ { "endToEndId" => "E1803615022211340s08793XPJ", "txid" => TXID, "chave" => "pix@alfa.com.br", "valor" => "1250.00", "horario" => "2026-10-25T13:40:34.000Z",
                            "infoPagador" => "pagando o pix", "gnExtras" => { "pagador" => { "nome" => "Maria Souza", "cpf" => "52998224725" } } } ] }.freeze

  def parse(body, account: @account, hmac: @hmac, ip: EFI_IP, verified: false)
    @efi.parse_notification(account, body: body.is_a?(String) ? body : body.to_json, headers: {}, context: { remote_ip: ip, query: { "hmac" => hmac }.compact, client_verified: verified })
  end

  test "Pix recebido: um aviso por endToEndId, com o txid, o valor em centavos e o horário; o pagador não vai adiante (R281)" do
    notification = parse(PIX_BODY).sole
    assert_equal [ "E1803615022211340s08793XPJ", :paid, TXID, 125_000, "E1803615022211340s08793XPJ" ], notification.to_h.values_at(:event_id, :kind, :external_id, :amount_cents, :end_to_end_id)
    assert_equal Time.utc(2026, 10, 25, 13, 40, 34), notification.occurred_at.utc
    assert_not_includes notification.to_h.to_s, "Maria"
    assert_not_includes notification.to_h.to_s, "52998224725"
  end

  test "Pix: o HMAC da URL com o IP da Efí autentica; sem o HMAC, com HMAC errado ou de IP desconhecido, não (IP-P4)" do
    assert_equal 1, parse(PIX_BODY).size
    [ { hmac: nil }, { hmac: "0" * 64 }, { ip: "203.0.113.9" }, { hmac: Payments::WebhookUrl.token(@account, "outro-segredo") } ].each do |options|
      assert_raises(Payments::Providers::InvalidSignature) { parse(PIX_BODY, **options) }
    end
  end

  test "Pix: o certificado de cliente verificado pelo proxy autentica só quando a instalação confia no cabeçalho (mTLS)" do
    assert_raises(Payments::Providers::InvalidSignature) { parse(PIX_BODY, hmac: nil, verified: true) }
    with_config(trust_mtls_header: true) { assert_equal 1, parse(PIX_BODY, hmac: nil, ip: "203.0.113.9", verified: true).size }
    with_config(trust_mtls_header: true) { assert_raises(Payments::Providers::InvalidSignature) { parse(PIX_BODY, hmac: nil, verified: false) } }
  end

  test "Pix: o HMAC da URL vale com o segredo anterior só durante a vigência dupla (R265)" do
    old_hmac = @hmac
    @account.reload.rotate_webhook_secret!
    assert_equal 1, parse(PIX_BODY, hmac: old_hmac).size
    travel(25.hours) { assert_raises(Payments::Providers::InvalidSignature) { parse(PIX_BODY, hmac: old_hmac) } }
  end

  test "devoluções do Pix: um aviso por devolução e estado; só DEVOLVIDO é devolução" do
    body = { "pix" => [ PIX_BODY["pix"].first.merge("devolucoes" => [
      { "id" => "123ABC", "rtrId" => "D1", "valor" => "300.00", "horario" => { "solicitacao" => "2026-10-25T14:00:00.000Z" }, "status" => "EM_PROCESSAMENTO" },
      { "id" => "123ABC", "rtrId" => "D1", "valor" => "300.00", "horario" => { "solicitacao" => "2026-10-25T14:00:00.000Z", "liquidacao" => "2026-10-25T14:01:00.000Z" }, "status" => "DEVOLVIDO" },
      { "id" => "456", "valor" => "10.00", "status" => "NAO_REALIZADO", "motivo" => "Saldo insuficiente para realizar a devolução." } ]) ] }
    notifications = parse(body)
    assert_equal [ :paid, :other, :refunded, :other ], notifications.map(&:kind)
    assert_equal 4, notifications.map(&:event_id).uniq.size
    assert_equal 30_000, notifications[2].amount_cents
    assert_equal "E1803615022211340s08793XPJ", notifications[2].end_to_end_id
  end

  test "corpo sem nada reconhecível (o teste do registro do webhook) devolve lista vazia; JSON inválido, erro" do
    assert_empty parse({})
    assert_empty parse("")
    assert_raises(Payments::Providers::Error) { parse("{isto não") }
  end

  test "cobranças: o aviso só traz o token (formulário ou JSON); a autenticação é o HMAC da URL; vale como pista, a verdade vem da consulta (R283)" do
    notification = parse("notification=abc123-TOKEN_xyz").sole
    assert_equal [ :check, "abc123-TOKEN_xyz", true ], [ notification.kind, notification.token, notification.reprocess ]
    assert_equal :check, parse({ "notification" => "abc123-TOKEN_xyz" }).sole.kind
    assert_raises(Payments::Providers::InvalidSignature) { parse("notification=abc123-TOKEN_xyz", hmac: nil) }
    assert_empty parse("notification=curto"), "token fora do formato não é aviso"
  end

  test "expand: a Efí troca o token pela lista de mudanças; cada mudança vira um aviso normalizado" do
    entries = { "code" => 200, "data" => [
      { "id" => 1, "type" => "charge", "custom_id" => "C" * 32, "status" => { "current" => "new", "previous" => nil }, "identifiers" => { "charge_id" => 5_078_130 }, "created_at" => "2026-10-20 10:00:00" },
      { "id" => 2, "type" => "charge", "custom_id" => "C" * 32, "status" => { "current" => "paid", "previous" => "waiting" }, "identifiers" => { "charge_id" => 5_078_130 },
        "received_by_bank_at" => "2026-10-25", "value" => 125_000, "created_at" => "2026-10-25 12:00:00" },
      { "id" => 3, "type" => "carnet", "status" => { "current" => "up_to_date" }, "identifiers" => { "carnet_id" => 9 } } ] }
    client = use_efi_client(efi_client.on(:get, "/v1/notification/", body: entries))
    billing = make_efi_account(@alfa, modality: "boleto")
    notification = Payments::Providers::Notification.new(event_id: "TOK-1234", kind: :check, token: "TOK-1234")
    expanded = @efi.expand_notification(billing, notification)
    assert_equal [ :other, :paid ], expanded.map(&:kind)
    paid = expanded.last
    assert_equal [ "5078130", 125_000, "C" * 32, "paid", "waiting" ], [ paid.external_id, paid.amount_cents, paid.custom_id, paid.current_status, paid.previous_status ]
    assert_equal "https://cobrancas-h.api.efipay.com.br/v1/notification/TOK-1234", client.to("/v1/notification/").first.url
  end

  test "expand de aviso que já é completo (Pix) devolve o próprio aviso, sem chamar a Efí" do
    notification = parse(PIX_BODY).sole
    assert_equal [ notification ], @efi.expand_notification(@account, notification)
  end

  test "consulta do Pix: pago e devolvido saem da lista pix[] e das devoluções DEVOLVIDO (R283)" do
    cobv = { "txid" => TXID, "status" => "CONCLUIDA", "valor" => { "original" => "1250.00" }, "calendario" => { "dataDeVencimento" => "2026-11-30" },
             "pix" => [ { "endToEndId" => "E1", "valor" => "1250.00", "devolucoes" => [ { "id" => "a", "valor" => "300.00", "status" => "DEVOLVIDO" }, { "id" => "b", "valor" => "50.00", "status" => "EM_PROCESSAMENTO" } ] } ] }
    use_efi_client(efi_client.on(:get, "/v2/cobv/#{TXID}", body: cobv))
    issued = @efi.fetch_pix(@account, TXID)
    assert_equal [ "paid", 125_000, 125_000, 30_000 ], [ issued.status, issued.amount_cents, issued.paid_cents, issued.refunded_cents ]
  end

  test "consulta do Pix ainda ativo não informa pago nem devolvido" do
    use_efi_client(efi_client.on(:get, "/v2/cobv/#{TXID}", body: { "txid" => TXID, "status" => "ATIVA", "valor" => { "original" => "10.00" } }))
    issued = @efi.fetch_pix(@account, TXID)
    assert_equal [ "active", nil, nil ], [ issued.status, issued.paid_cents, issued.refunded_cents ]
  end

  test "consulta de cartão reembolsado: continua pago, com o total devolvido; boleto pago traz o total" do
    card = make_efi_account(@alfa, modality: "card")
    use_efi_client(efi_client.on(:get, "/v1/charge/77", body: { "code" => 200, "data" => { "charge_id" => 77, "status" => "refunded", "total" => 90_000 } })
                              .on(:get, "/v1/charge/78", body: { "code" => 200, "data" => { "charge_id" => 78, "status" => "paid", "total" => 125_000, "payment" => "banking_billet" } }))
    refunded = @efi.fetch_card(card, "77")
    assert_equal [ "paid", 90_000, 90_000 ], [ refunded.status, refunded.paid_cents, refunded.refunded_cents ]
    assert_equal [ "paid", 125_000 ], @efi.fetch_boleto(make_efi_account(@alfa, modality: "boleto"), "78").then { |issued| [ issued.status, issued.paid_cents ] }
  end

  test "a emissão e a cobrança de cartão mandam a URL do webhook da conta como notification_url" do
    with_config(public_url: "https://crm.exemplo.com.br") do
      billing = make_efi_account(@alfa, modality: "boleto")
      billing.rotate_webhook_secret!
      url = Payments::WebhookUrl.for(billing)
      assert_match(%r{\Ahttps://crm\.exemplo\.com\.br/webhooks/pagamentos/contas/#{billing.id}\?hmac=\h{64}\z}, url)
      client = use_efi_client(efi_client.on(:post, "/v1/charge/one-step", body: { "code" => 200, "data" => { "charge_id" => 5_078_130, "total" => 125_000, "status" => "waiting", "barcode" => "34191.09008", "expire_at" => "2026-11-30" } }))
      @efi.issue_boleto(billing, custom_id: "C" * 32, amount_cents: 125_000, due_on: Date.new(2026, 11, 30), payer: { name: "Maria", document: "52998224725" }, options: { notification_url: url })
      assert_equal url, JSON.parse(client.to("/v1/charge/one-step").first.body).dig("metadata", "notification_url")
    end
  end

  test "a cobrança de cartão leva a mesma notification_url nos metadados" do
    card = make_efi_account(@alfa, modality: "card")
    client = use_efi_client(efi_client.on(:post, "/v1/charge/one-step", body: { "code" => 200, "data" => { "charge_id" => 5, "total" => 1_000, "status" => "approved", "installments" => 1 } }))
    @efi.charge_card(card, custom_id: "K" * 32, amount_cents: 1_000, installments: 1, payment_token: "TOKEN-DO-NAVEGADOR-1", payer: { name: "Maria", document: "52998224725" },
                           notification_url: "https://crm.exemplo.com.br/webhooks/pagamentos/contas/1?hmac=abc")
    assert_equal "https://crm.exemplo.com.br/webhooks/pagamentos/contas/1?hmac=abc", JSON.parse(client.to("/v1/charge/one-step").first.body).dig("metadata", "notification_url")
  end

  test "registrar o webhook do Pix: PUT na chave com a URL, ignorar e o cabeçalho que dispensa o mTLS nosso" do
    with_config(public_url: "https://crm.exemplo.com.br") do
      client = use_efi_client(efi_client.on(:put, "/v2/webhook/", status: 201, body: {}))
      assert @efi.register_pix_webhook(@account)
      request = client.to("/v2/webhook/pix%40alfa.com.br").first
      assert_equal "true", request.headers["x-skip-mtls-checking"]
      assert_equal "#{Payments::WebhookUrl.for(@account)}&ignorar=", JSON.parse(request.body)["webhookUrl"]
    end
    with_config(public_url: nil) { assert_raises(Payments::Providers::Error) { @efi.register_pix_webhook(@account) } }
  end

  private
    def with_config(**values)
      config = Rails.configuration.x.payments
      old = values.keys.to_h { |key| [ key, config.public_send(key) ] }
      values.each { |key, value| config.public_send("#{key}=", value) }
      yield
    ensure
      old.each { |key, value| config.public_send("#{key}=", value) }
    end
end
