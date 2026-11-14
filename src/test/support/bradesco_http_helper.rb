# O Bradesco nos testes (12, revisão 4): o mesmo cliente HTTP falso da Efí, com respostas gravadas à mão a partir dos exemplos dos manuais, e uma
# autenticação de teste para a API de cobrança (a de verdade espera o documento do banco, bloqueio B1). Nenhum teste chama o Bradesco.
module BradescoHttpHelper
  # Autenticação de teste da API de cobrança: marca o pedido com um cabeçalho, para os testes conferirem que ela foi usada.
  class TestBoletoAuth
    def configured? = true

    def headers(_account, method:, path:, body:) = { "X-Autenticacao-De-Teste" => "#{method.to_s.upcase} #{path} #{Digest::SHA256.hexdigest(body)[0, 8]}" }

    def tls(_account) = nil
  end

  def use_bradesco_client(client)
    Payments::Providers::Bradesco.http_client = client
    client
  end

  def with_bradesco_boleto_auth
    Payments::Providers::Bradesco.boleto_auth = TestBoletoAuth.new
    yield
  ensure
    Payments::Providers::Bradesco.boleto_auth = nil
  end

  # Falso já com o token do Pix respondido.
  def bradesco_client = EfiHttpHelper::FakeClient.new.on(:post, "/oauth/token", body: { "access_token" => "TOKEN-PIX-BRADESCO", "token_type" => "Bearer", "expires_in" => 3600 })

  # Integração Bradesco pronta. Pix: credenciais e .p12; boleto: beneficiário e contrato do exemplo do manual (agência 2856, conta 0222652, carteira 09).
  def make_bradesco_account(tenant, modality: "pix", environment: "sandbox", nickname: nil, config: {})
    channel = tenant.payment_channels.first || make_channel(tenant)
    account = tenant.payment_accounts.build(channel: channel, modality: modality, provider: "bradesco", environment: environment,
                                            nickname: nickname || "Bradesco #{modality} #{SecureRandom.hex(2)}")
    files = {}
    secrets = {}
    base = if modality == "pix"
      secrets = { "client_id" => "Bradesco_Id_#{SecureRandom.hex(4)}", "client_secret" => "Bradesco_Secret_#{SecureRandom.hex(4)}" }
      file = Tempfile.new([ "cert", ".p12" ], binmode: true)
      file.write(make_p12)
      file.flush
      (@bradesco_files ||= []) << file
      files["certificate"] = Rack::Test::UploadedFile.new(file.path, "application/x-pkcs12", true)
      { "pix_key" => "pix@alfa.com.br", "qr_name" => "ESCOLA ALFA", "fine_percent" => 2, "interest_percent" => 1 }
    else
      { "beneficiary_name" => "Escola Alfa Ltda", "beneficiary_document" => "41755489000155", "agency" => "2856", "agency_digit" => "1", "account_number" => "0222652",
        "account_digit" => "7", "wallet" => 9, "species" => "ME", "our_number_start" => 52_280_000_490, "fine_percent" => 2, "interest_percent" => 1, "write_off_days" => 30 }
    end
    account.assign_values(config: base.merge(config), secrets: secrets, files: files)
    account.save!
    account
  end
end
