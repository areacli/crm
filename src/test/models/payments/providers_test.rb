require "test_helper"

# Registro, manifesto e contratos dos fornecedores (12, R258, R259, R266) e o adaptador falso.
class ProvidersTest < ActiveSupport::TestCase
  setup do
    Payments::Providers::Fake.reset!
    @alfa = tenants(:alfa)
    @fake = Payments::Providers.adapter(:fake)
  end

  test "o registro conhece o falso e a Efí, e cada um declara o manifesto (R258)" do
    assert_equal %w[fake efi].sort, Payments::Providers.names.sort
    assert_raises(Payments::Providers::UnknownProvider) { Payments::Providers.adapter("nenhum") }
    %w[fake efi].each do |name|
      manifest = Payments::Providers.manifest(name)
      assert_equal name, manifest.provider
      assert_equal %w[boleto pix card], manifest.modalities
      assert_equal manifest.modalities.sort, Payments::Providers.adapter(name).modalities.sort, "o manifesto bate com os contratos incluídos"
    end
  end

  test "os tipos de campo do manifesto são os cinco e o tipo desconhecido é recusado (R259)" do
    assert_equal %w[text secret file select number].sort, Payments::Providers::Manifest::TYPES.sort
    assert_raises(ArgumentError) { Payments::Providers::Manifest::Field.new(name: "x", type: :boolean) }
  end

  test "o manifesto da Efí descreve os campos pedidos por modalidade (R259)" do
    manifest = Payments::Providers.manifest(:efi)
    names = ->(modality) { manifest.fields_for(modality).map(&:name) }
    assert_includes names.call("pix"), "certificate"
    assert_includes names.call("pix"), "pix_key"
    assert_includes names.call("pix"), "certificate_password"
    assert_not_includes names.call("boleto"), "certificate"
    assert_not_includes names.call("boleto"), "pix_key"
    assert_includes names.call("card"), "payee_code"
    assert_includes names.call("boleto"), "write_off_days"
    assert_equal %w[secret secret file], %w[client_id client_secret certificate].map { |name| manifest.field(name).type }
    assert(manifest.field("certificate").certificate?)
    assert(manifest.field("client_secret").secret?)
    assert(manifest.field("webhook_secret").generated)
  end

  test "um fornecedor lista só as modalidades que implementa" do
    only_boleto = Class.new(Payments::Providers::Base) { include Payments::Providers::Boleto }.new
    assert_equal %w[boleto], only_boleto.modalities
    assert only_boleto.supports?(:boleto)
    assert_not only_boleto.supports?(:pix)
    assert_raises(NotImplementedError) { only_boleto.fetch_boleto(nil, "x") }
    assert_raises(NoMethodError) { only_boleto.issue_pix(nil, custom_id: "a", amount_cents: 1, due_on: Date.current, payer: {}) }
  end

  test "o falso emite boleto com linha digitável e PDF e devolve o mesmo para o mesmo custom_id (R258)" do
    issued = @fake.issue_boleto(nil, custom_id: "C-1", amount_cents: 125_000, due_on: Date.new(2026, 11, 30), payer: { name: "Maria" })
    assert_equal "active", issued.status
    assert_equal 125_000, issued.amount_cents
    assert_match(/\A\d{5}\.\d{5} \d{5}\.\d{6} \d{5}\.\d{6} \d \d{14}\z/, issued.digitable_line)
    assert issued.pdf.start_with?("%PDF")
    assert_equal issued.external_id, @fake.issue_boleto(nil, custom_id: "C-1", amount_cents: 125_000, due_on: Date.new(2026, 11, 30), payer: {}).external_id
    assert_equal issued.external_id, @fake.fetch_boleto(nil, issued.external_id).external_id
  end

  test "o falso emite Pix com copia e cola e QR Code, cancela, devolve e muda vencimento (R258)" do
    pix = @fake.issue_pix(nil, custom_id: "P-1", amount_cents: 1_000, due_on: Date.current, payer: {})
    assert pix.copy_paste.start_with?("00020126")
    assert pix.qr_png.start_with?("\x89PNG".b)
    assert_equal "canceled", @fake.cancel_pix(nil, pix.external_id).status
    refunded = @fake.issue_pix(nil, custom_id: "P-2", amount_cents: 1_000, due_on: Date.current, payer: {})
    assert_raises(Payments::Providers::Error) { @fake.refund_pix(nil, refunded.external_id, amount_cents: 1_001) }
    assert_equal 1_000, @fake.refund_pix(nil, refunded.external_id, amount_cents: 400).amount_cents
    boleto = @fake.issue_boleto(nil, custom_id: "B-2", amount_cents: 500, due_on: Date.current, payer: {})
    assert_equal Date.current + 5, @fake.change_boleto_due_date(nil, boleto.external_id, Date.current + 5).due_on
  end

  test "o falso cobra o cartão pelo token e recusa o token recusado (R278)" do
    assert_equal "approved", @fake.charge_card(nil, custom_id: "K-1", amount_cents: 9_000, installments: 3, payment_token: "tok_ok", payer: {}).status
    refused = @fake.charge_card(nil, custom_id: "K-2", amount_cents: 9_000, installments: 1, payment_token: "recusado", payer: {})
    assert_equal [ "declined", "security", false ], [ refused.status, refused.refusal_code, refused.retry ]
    assert_equal 12, @fake.installments(nil, amount_cents: 9_000).size
  end

  test "o falso lê o aviso assinado e recusa a assinatura errada (R281)" do
    account = make_account(@alfa)
    secret = account.rotate_webhook_secret!
    body = { id: "EV-1", type: "paid", external_id: "FAKE-BOLETO-1", amount_cents: 125_000 }.to_json
    signature = OpenSSL::HMAC.hexdigest("SHA256", secret, body)
    events = @fake.parse_notification(account, body: body, headers: { "X-Signature" => signature })
    assert_equal [ "EV-1", :paid, 125_000 ], [ events.first.event_id, events.first.kind, events.first.amount_cents ]
    assert_raises(Payments::Providers::Error) { @fake.parse_notification(account, body: body, headers: { "X-Signature" => "errada" }) }
  end

  test "o teste de conexão do falso responde conforme a configuração e o da Efí ainda não existe (R266)" do
    ok = make_account(@alfa, nickname: "ok")
    refused = make_account(@alfa, nickname: "recusada", environment: "production", config: { "connection_result" => "refused" })
    unavailable = make_account(@alfa, nickname: "fora", modality: "card", config: { "connection_result" => "unavailable" })
    assert Payments::AccountTester.new.call(ok).ok?
    result = Payments::AccountTester.new.call(refused)
    assert_equal [ false, "Credencial recusada pelo fornecedor." ], [ result.ok, result.message ]
    assert_equal "failed", refused.reload.last_test_status
    assert_equal [ false, "Fornecedor indisponível." ], Payments::AccountTester.new.call(unavailable).then { |r| [ r.ok, r.message ] }

    efi = @alfa.payment_accounts.build(channel: ok.channel, modality: "boleto", provider: "efi", environment: "production", nickname: "Efí boleto", active: false)
    efi.assign_values(secrets: { "client_id" => "id", "client_secret" => "segredo" })
    efi.save!
    use_efi_client(efi_client.on(:post, "/v1/authorize", status: 401, body: { "error" => "invalid_client" }))
    result = Payments::AccountTester.new.call(efi)
    assert_equal false, result.ok
    assert_match(/Credencial recusada pela Efí/, result.message)
    assert_equal "failed", efi.reload.last_test_status
  end

  test "o teste acusa certificado vencido antes de chamar o fornecedor (R266)" do
    account = make_account(@alfa, modality: "pix", config: { "connection_result" => "ok", "pix_key" => "p@a.com" })
    account.update_columns(file_details: { "certificate" => { "subject" => "CN=X", "not_after" => (Date.current - 1).iso8601, "sha256" => "AA" } })
    result = Payments::AccountTester.new.call(account)
    assert_equal [ false, "O certificado venceu em #{(Date.current - 1).strftime('%d/%m/%Y')}." ], [ result.ok, result.message ]
  end
end
