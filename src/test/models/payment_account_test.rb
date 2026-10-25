require "test_helper"

# Conta de pagamento (12): regras R259 a R262, R265 e R269 no modelo.
class PaymentAccountTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    make_channel(@alfa)
  end

  test "a conta nasce ativa com os padrões do manifesto e o segredo cifrado (R259, R260, R262)" do
    secret = sentinel("api")
    account = make_account(@alfa, secrets: { "api_key" => secret }, config: { "connection_result" => "ok" })
    assert account.active?
    assert_equal 5, account.config["expire_days"]
    assert_equal secret, account.reload.secrets["api_key"]
    raw = account.secrets_before_type_cast
    assert_not_includes raw, secret
    assert_not_nil ActiveRecord::Encryption.message_serializer.load(raw).headers.encrypted_data_key_id, "o cabeçalho guarda a referência da chave (R254)"
  end

  test "campo obrigatório do manifesto vazio recusa a gravação com o nome do campo (R259)" do
    account = @alfa.payment_accounts.build(channel: @alfa.payment_channels.first, modality: "pix", provider: "fake", environment: "sandbox", nickname: "Pix sem chave")
    account.assign_values(config: { "connection_result" => "ok" }, secrets: { "api_key" => "x" })
    assert_not account.valid?
    assert_includes account.errors.full_messages.to_sentence, "Chave Pix é obrigatório"
  end

  test "número fora dos limites e opção inválida são recusados (R259)" do
    account = @alfa.payment_accounts.build(channel: @alfa.payment_channels.first, modality: "boleto", provider: "fake", environment: "sandbox", nickname: "Ruim")
    account.assign_values(config: { "connection_result" => "talvez", "expire_days" => "400" }, secrets: { "api_key" => "x" })
    assert_not account.valid?
    messages = account.errors.full_messages.to_sentence
    assert_includes messages, "Dias de validade deve estar entre 1 e 365"
    assert_includes messages, "Resultado do teste de conexão: escolha uma das opções"
  end

  test "uma conta ativa por credor, modalidade e ambiente; outro ambiente, outra modalidade e a desativada valem (R260)" do
    make_account(@alfa, modality: "boleto", environment: "production", nickname: "Boleto produção")
    other = @alfa.payment_accounts.build(channel: @alfa.payment_channels.first, modality: "boleto", provider: "fake", environment: "production", nickname: "Outra")
    other.assign_values(config: { "connection_result" => "ok" }, secrets: { "api_key" => "x" })
    assert_not other.valid?
    assert_includes other.errors.full_messages.to_sentence, "Já existe uma conta de Boleto ativa neste ambiente (Produção)"

    make_account(@alfa, modality: "boleto", environment: "sandbox", nickname: "Boleto homologação")
    make_account(@alfa, modality: "card", environment: "production", nickname: "Cartão produção")
    make_account(@alfa, modality: "boleto", environment: "production", nickname: "Boleto desativado", active: false)
    make_account(@beta, modality: "boleto", environment: "production", nickname: "Boleto produção")
    assert_equal 2, PaymentAccount.where(nickname: "Boleto produção").count, "o apelido só é único dentro do credor"
  end

  test "o banco também garante uma conta ativa por modalidade e ambiente (R260)" do
    make_account(@alfa, modality: "pix", environment: "production", nickname: "Pix 1", config: { "connection_result" => "ok", "pix_key" => "a@b.com" })
    clone = PaymentAccount.new(tenant: @alfa, channel: @alfa.payment_channels.first, modality: "pix", provider: "fake", environment: "production", nickname: "Pix 2", config: {}, active: true)
    assert_raises(ActiveRecord::RecordNotUnique) { clone.save!(validate: false) }
  end

  test "o canal tem de ser do mesmo credor e o fornecedor tem de existir e atender a modalidade (R260)" do
    beta_channel = make_channel(@beta, code: "BETA-1")
    account = @alfa.payment_accounts.build(channel: beta_channel, modality: "boleto", provider: "inexistente", environment: "sandbox", nickname: "X")
    assert_not account.valid?
    assert_includes account.errors.full_messages.to_sentence, "Canal é de outro credor"
    assert_includes account.errors.full_messages.to_sentence, "Fornecedor não está instalado neste sistema"
  end

  test "o segredo do webhook anterior vale por 24 horas depois da troca (R265)" do
    account = make_account(@alfa)
    now = Time.zone.parse("2026-10-05 10:00")
    first = account.rotate_webhook_secret!(now: now)
    assert_equal [ first ], account.webhook_secrets(now: now)
    second = account.rotate_webhook_secret!(now: now)
    assert_equal [ second, first ], account.webhook_secrets(now: now + 10.hours)
    assert_equal [ second ], account.webhook_secrets(now: now + 25.hours)
    assert_not_equal first, second
  end

  test "enviar o certificado guarda cifrado só o conteúdo e expõe titular, validade e impressão digital (R263)" do
    account = make_account(@alfa, modality: "pix", config: { "connection_result" => "ok", "pix_key" => "pix@alfa.com.br" })
    upload = p12_upload(subject: "CN=Escola Alfa", days: 200, password: "abc123")
    account.assign_values(secrets: { "certificate_password" => "abc123" }, files: { "certificate" => upload })
    account.save!
    info = account.reload.file_info("certificate")
    assert_equal "CN=Escola Alfa", info["subject"]
    assert_equal (Date.current + 200).iso8601, info["not_after"]
    assert_match(/\A([0-9A-F]{2}:){31}[0-9A-F]{2}\z/, info["sha256"])
    assert_equal Date.current + 200, account.certificate_expires_on
    assert_not_includes account.secrets_before_type_cast, "abc123"
    assert_equal [ "certificate" ], account.replaced_files
  end

  test "certificado que não presta recusa a gravação com a mensagem da regra (R263)" do
    account = make_account(@alfa, modality: "pix", config: { "connection_result" => "ok", "pix_key" => "pix@alfa.com.br" })
    {
      "Não foi possível abrir o certificado" => { files: { "certificate" => p12_upload(password: "certa") }, secrets: { "certificate_password" => "errada" } },
      "O arquivo não tem a chave privada" => { files: { "certificate" => p12_upload(with_key: false) } },
      "O certificado venceu em #{(Date.current - 5).strftime('%d/%m/%Y')}" => { files: { "certificate" => p12_upload(days: -5) } }
    }.each do |expected, values|
      candidate = PaymentAccount.find(account.id)
      candidate.assign_values(**values)
      assert_not candidate.valid?, expected
      assert_includes candidate.errors.full_messages.to_sentence, expected
    end
    corrupt = Tempfile.new([ "ruim", ".p12" ])
    corrupt.write("isto não é um certificado")
    corrupt.flush
    candidate = PaymentAccount.find(account.id)
    candidate.assign_values(files: { "certificate" => Rack::Test::UploadedFile.new(corrupt.path) })
    assert_not candidate.valid?
    assert_includes candidate.errors.full_messages.to_sentence, "Não foi possível abrir o certificado"
  end

  test "o arquivo novo usa a senha enviada, não a do arquivo anterior (R263)" do
    account = make_account(@alfa, modality: "pix", config: { "connection_result" => "ok", "pix_key" => "pix@alfa.com.br" })
    account.assign_values(secrets: { "certificate_password" => "primeira" }, files: { "certificate" => p12_upload(password: "primeira") })
    account.save!
    account.assign_values(files: { "certificate" => p12_upload(password: "") })
    assert account.save, account.errors.full_messages.to_sentence
    assert_not account.reload.secret_set?("certificate_password")
  end

  test "trocar o certificado zera o controle do aviso de vencimento (R264)" do
    account = make_account(@alfa, modality: "pix", config: { "connection_result" => "ok", "pix_key" => "pix@alfa.com.br" })
    account.assign_values(files: { "certificate" => p12_upload(days: 20) })
    account.save!
    account.update_columns(certificate_warned_for: Date.current + 20)
    account.assign_values(files: { "certificate" => p12_upload(days: 400) })
    account.save!
    assert_nil account.reload.certificate_warned_for
  end

  test "o canal com conta de pagamento não se apaga (R269)" do
    account = make_account(@alfa)
    assert_raises(Access::Refused) { Payments::ChannelManager.new(users(:joana)).destroy(account.channel) }
  end
end
