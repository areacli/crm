require "test_helper"

# Segredos fora de log, de HTML e de fixture (12, R261, R262, R270): varre as colunas `encrypts` de todos os modelos.
class EncryptionArchitectureTest < ActionDispatch::IntegrationTest
  test "toda coluna cifrada está na lista de atributos conhecidos (um modelo novo com `encrypts` entra aqui de propósito)" do
    assert_equal [ "PaymentAccount.secrets", "PaymentChannel.webhook_secret" ], KeyRotation.targets.map { |model, attribute| "#{model.name}.#{attribute}" }.sort
  end

  test "nenhum valor de coluna cifrada aparece no log de teste nem no HTML devolvido" do
    secrets = { api_key: sentinel("api"), certificate_password: sentinel("senha"), webhook: nil }
    alfa = tenants(:alfa)
    channel = make_channel(alfa)
    post session_path, params: { email_address: users(:joana).email_address, password: "senha-de-teste-1" }

    post settings_payment_accounts_path, params: { payment_account: { tenant_id: alfa.id, channel_id: channel.id, modality: "pix", provider: "fake", environment: "sandbox", nickname: "Arquitetura",
                                                                       config: { connection_result: "ok", pix_key: "pix@alfa.com.br" },
                                                                       secrets: { api_key: secrets[:api_key], certificate_password: secrets[:certificate_password] },
                                                                       files: { certificate: p12_upload(password: secrets[:certificate_password]) } } }
    account = PaymentAccount.find_by!(nickname: "Arquitetura")
    bodies = [ response.body ]
    post settings_payment_account_webhook_secret_path(account)
    webhook_secret = flash[:webhook_secret]
    post settings_payment_account_connection_test_path(account)
    channel.regenerate_webhook_secret!
    [ settings_payment_accounts_path, edit_settings_payment_account_path(account), edit_settings_channel_path(channel), settings_channels_path ].each do |path|
      get path
      bodies << response.body
    end
    values = secrets.values.compact + [ channel.reload.webhook_secret, account.reload.secrets["certificate"] ]
    values.each { |value| bodies.each { |body| assert_not_includes body, value, "valor secreto apareceu no HTML" } }

    Rails.logger.flush if Rails.logger.respond_to?(:flush)
    log = Rails.root.join("log/test.log")
    text = File.exist?(log) ? File.binread(log).force_encoding("UTF-8").scrub : ""
    ([ webhook_secret ] + values).each do |value|
      next if value.blank? || value == webhook_secret && false

      assert_not_includes text, value, "valor secreto apareceu no log de teste"
    end
    assert_includes text, "Processing by Settings::PaymentAccountsController#create", "o log do teste foi lido"
  end

  test "nenhuma fixture define coluna cifrada" do
    KeyRotation.targets.each do |model, attribute|
      file = Rails.root.join("test/fixtures/#{model.table_name}.yml")
      assert_not File.exist?(file) && File.read(file).match?(/^\s+#{attribute}:/), "#{file} define #{attribute}, que é cifrada"
    end
  end

  test "os parâmetros filtrados cobrem p12, client_id e client_secret e o filtro esconde os valores" do
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter("client_id" => "abc", "client_secret" => "def", "files" => { "p12" => "bytes" }, "arquivo_p12" => "x", "nickname" => "ok")
    assert_equal "ok", filtered["nickname"]
    assert_equal [ "[FILTERED]" ] * 3, filtered.values_at("client_id", "client_secret", "arquivo_p12")
    assert_equal({ "p12" => "[FILTERED]" }, filtered["files"])
  end

  test "as chaves de criptografia não são derivadas do secret_key_base: vêm das credenciais do ambiente (R252)" do
    assert_not File.exist?(Rails.root.join("config/initializers/active_record_encryption.rb"))
    credentials = Rails.application.credentials.active_record_encryption
    assert_equal credentials[:key_derivation_salt], ActiveRecord::Encryption.config.key_derivation_salt
    assert_equal Array(credentials[:primary_key]), Array(ActiveRecord::Encryption.config.primary_key)
    assert_not_equal Rails.application.key_generator.generate_key("active_record_encryption.key_derivation_salt", 32).unpack1("H*"), credentials[:key_derivation_salt]
  end

  test "o back office não tem rota nem controlador para emitir instrumento (R270)" do
    routes = Rails.application.routes.routes.reject { |route| route.verb == "" || route.path.spec.to_s.start_with?("/rails/", "/cable", "/pagar/", "/webhooks/") } # a página pública de pagamento e os webhooks têm teste próprio (checkout_test e webhook_accounts_test)
    suspicious = routes.select { |route| "#{route.path.spec} #{route.defaults[:controller]}".match?(/emit|emiss|issue|boleto|\/pix|instrument|instrumento/i) }
    # A única exceção são as leituras de instrumento já emitido (R275): só GET, sem ação de criar, atualizar ou apagar.
    assert_empty suspicious.reject { |route| route.verb == "GET" && route.defaults[:controller].to_s.start_with?("payment_instruments") && route.defaults[:action] == "show" },
                 "rota de emissão no back office"
    controllers = Dir[Rails.root.join("app/controllers/**/*.rb")].map { |file| File.basename(file) }
    assert_empty controllers.grep(/issuer|emission|emit/i)
    assert_empty Dir[Rails.root.join("app/views/**/*instrument*")], "tela de instrumento no back office"
  end
end
