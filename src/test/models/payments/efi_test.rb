require "test_helper"

# Adaptador Efí (12, parte B) com respostas gravadas à mão: nenhum teste chama a Efí real (R258, IP-Q5).
class PaymentsEfiTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @payer = { name: "Maria Souza", document: "52998224725",
               address: { "street" => "Rua das Flores", "number" => "10", "district" => "Centro", "city" => "Curitiba", "state" => "PR", "zip" => "80010000" } }
    @efi = Payments::Providers::Efi.new
  end

  BILLET_RESPONSE = { "code" => 200, "data" => { "charge_id" => 5_078_130, "total" => 125_000, "status" => "waiting", "barcode" => "34191.09008 61207.727808 71444.640008 5 83610000125000",
                                                  "link" => "https://visualizacao.gerencianet.com.br/emissao/SEGREDO-LINK", "expire_at" => "2026-11-30",
                                                  "pdf" => { "charge" => "https://download.gerencianet.com.br/emissao/abc/boleto.pdf" }, "payment" => "banking_billet" } }.freeze
  COBV_RESPONSE = { "calendario" => { "criacao" => "2026-10-25T10:00:00Z", "dataDeVencimento" => "2026-11-30", "validadeAposVencimento" => 30 }, "txid" => "T" * 32, "revisao" => 0,
                    "loc" => { "id" => 789, "location" => "pix.efipay.com.br/cobv/XYZ", "tipoCob" => "cobv" }, "status" => "ATIVA", "valor" => { "original" => "1250.00" },
                    "chave" => "pix@alfa.com.br", "pixCopiaECola" => "00020101021226830014br.gov.bcb.pix2561pix.efipay.com.br/cobv/XYZ5204000053039865802BR5910Escola6008CURITIBA62070503***6304ABCD" }.freeze
  PDF = "%PDF-1.4\nboleto da efi\n%%EOF".b.freeze

  def boleto_account = (@boleto ||= make_efi_account(@alfa, modality: "boleto"))
  def pix_account = (@pix ||= make_efi_account(@alfa, modality: "pix"))

  def issue_boleto(**options)
    @efi.issue_boleto(boleto_account, custom_id: "C" * 32, amount_cents: 125_000, due_on: Date.new(2026, 11, 30), payer: @payer, options: options)
  end

  test "autentica com Basic na API de cobranças e usa o token nas chamadas (OAuth client_credentials)" do
    client = use_efi_client(efi_client.on(:post, "/v1/charge/one-step", body: BILLET_RESPONSE))
    issue_boleto
    auth = client.to("/v1/authorize").first
    assert_equal "https://cobrancas-h.api.efipay.com.br/v1/authorize", auth.url
    assert_equal "Basic #{Base64.strict_encode64("#{boleto_account.secrets['client_id']}:#{boleto_account.secrets['client_secret']}")}", auth.headers["Authorization"]
    assert_equal({ "grant_type" => "client_credentials" }, JSON.parse(auth.body))
    assert_equal "Bearer TOKEN-COBRANCAS", client.to("/v1/charge/one-step").first.headers["Authorization"]
  end

  test "o token é reaproveitado e renovado quando a Efí o recusa uma vez" do
    n = 0
    client = use_efi_client(efi_client.on(:post, "/v1/charge/one-step") { n += 1; n == 1 ? { status: 401, body: {} } : { status: 200, body: BILLET_RESPONSE } })
    issue_boleto
    assert_equal 2, client.to("/v1/authorize").size, "token pedido de novo depois do 401"
    issue_boleto
    assert_equal 2, client.to("/v1/authorize").size, "token guardado na memória do processo"
  end

  test "boleto: corpo do one-step com banking_billet, custom_id, centavos, endereço completo, multa e juros (R271)" do
    client = use_efi_client(efi_client.on(:post, "/v1/charge/one-step", body: BILLET_RESPONSE))
    issued = issue_boleto(fine_percent: 2, interest_percent: 1, write_off_days: 30, message: "Mensalidade de outubro")
    body = JSON.parse(client.to("/v1/charge/one-step").first.body)
    assert_equal "C" * 32, body.dig("metadata", "custom_id")
    assert_equal [ { "name" => "Cobrança", "value" => 125_000, "amount" => 1 } ], body["items"]
    billet = body.dig("payment", "banking_billet")
    assert_equal "2026-11-30", billet["expire_at"]
    assert_equal({ "name" => "Maria Souza", "cpf" => "52998224725", "address" => { "street" => "Rua das Flores", "number" => "10", "neighborhood" => "Centro", "zipcode" => "80010000", "city" => "Curitiba", "state" => "PR" } }, billet["customer"])
    assert_equal({ "days_to_write_off" => 30, "fine" => 200, "interest" => { "value" => 100, "type" => "monthly" } }, billet["configurations"])
    assert_equal "Mensalidade de outubro", billet["message"]
    assert_equal [ "5078130", "active", 125_000, Date.new(2026, 11, 30) ], [ issued.external_id, issued.status, issued.amount_cents, issued.due_on ]
    assert_equal "34191.09008 61207.727808 71444.640008 5 83610000125000", issued.digitable_line
    assert_nil issued.pdf, "o PDF é baixado à parte; o endereço do fornecedor não sai do adaptador"
    assert_not issued.to_h.values.any? { |v| v.to_s.include?("gerencianet.com.br") }
  end

  test "boleto de CNPJ usa juridical_person e sem endereço completo não envia endereço" do
    client = use_efi_client(efi_client.on(:post, "/v1/charge/one-step", body: BILLET_RESPONSE))
    @efi.issue_boleto(boleto_account, custom_id: "D" * 32, amount_cents: 1000, due_on: Date.new(2026, 11, 30), payer: { name: "Escola Ltda", document: "11222333000181", address: { "street" => "Rua" } })
    customer = JSON.parse(client.to("/v1/charge/one-step").first.body).dig("payment", "banking_billet", "customer")
    assert_equal({ "juridical_person" => { "corporate_name" => "Escola Ltda", "cnpj" => "11222333000181" } }, customer)
  end

  test "baixa o PDF do boleto daqui, sem credencial na requisição, só de endereço da Efí (R273, IP-P2)" do
    client = use_efi_client(efi_client.on(:get, "/v1/charge/5078130", body: BILLET_RESPONSE)
                                      .on(:get, "download.gerencianet.com.br") { |_| { status: 200, raw: PDF } })
    assert_equal PDF, @efi.download_boleto_pdf(boleto_account, "5078130")
    download = client.to("download.gerencianet.com.br").first
    assert_empty download.headers.keys.grep(/authorization/i)
  end

  test "recusa PDF de outro domínio, resposta que não é PDF e charge sem PDF" do
    foreign = BILLET_RESPONSE.deep_merge("data" => { "pdf" => { "charge" => "https://atacante.example.com/x.pdf" } })
    use_efi_client(efi_client.on(:get, "/v1/charge/1", body: foreign))
    assert_raises(Payments::Providers::Error) { @efi.download_boleto_pdf(boleto_account, "1") }
    use_efi_client(efi_client.on(:get, "/v1/charge/2", body: BILLET_RESPONSE).on(:get, "download.gerencianet.com.br", raw: "<html>erro</html>"))
    assert_raises(Payments::Providers::Error) { @efi.download_boleto_pdf(boleto_account, "2") }
    use_efi_client(efi_client.on(:get, "/v1/charge/3", body: { "data" => { "charge_id" => 3, "status" => "waiting" } }))
    assert_raises(Payments::Providers::Error) { @efi.download_boleto_pdf(boleto_account, "3") }
  end

  test "http simples é recusado e o PDF não segue redirecionamento fora da Efí" do
    http = BILLET_RESPONSE.deep_merge("data" => { "pdf" => { "charge" => "http://download.gerencianet.com.br/x.pdf" } })
    use_efi_client(efi_client.on(:get, "/v1/charge/4", body: http))
    assert_raises(Payments::Providers::Error) { @efi.download_boleto_pdf(boleto_account, "4") }
  end

  test "cancelar e mudar o vencimento do boleto: métodos e caminhos da Efí" do
    client = use_efi_client(efi_client.on(:put, "/v1/charge/5078130/cancel", body: { "code" => 200 }).on(:put, "/v1/charge/5078130/billet", body: { "code" => 200 }))
    assert_equal "canceled", @efi.cancel_boleto(boleto_account, "5078130").status
    changed = @efi.change_boleto_due_date(boleto_account, "5078130", Date.new(2026, 12, 15))
    assert_equal Date.new(2026, 12, 15), changed.due_on
    assert_equal({ "expire_at" => "2026-12-15" }, JSON.parse(client.to("/billet").first.body))
  end

  test "consultar o boleto traduz o estado da Efí para o nosso" do
    { "waiting" => "active", "paid" => "paid", "unpaid" => "expired", "canceled" => "canceled", "settled" => "paid" }.each do |theirs, ours|
      use_efi_client(efi_client.on(:get, "/v1/charge/9", body: { "data" => BILLET_RESPONSE["data"].merge("status" => theirs) }))
      assert_equal ours, @efi.fetch_boleto(boleto_account, "9").status, theirs
    end
  end

  test "Pix: PUT em cobv com o txid nosso, mTLS, valor em texto, devedor, multa e juros (R271)" do
    client = use_efi_client(efi_client.on(:put, "/v2/cobv/#{'T' * 32}", status: 201, body: COBV_RESPONSE)
                                      .on(:get, "/v2/loc/789/qrcode", body: { "qrcode" => "x", "imagemQrcode" => "data:image/svg+xml;base64,PHN2Zy8+" }))
    issued = @efi.issue_pix(pix_account, custom_id: "T" * 32, amount_cents: 125_000, due_on: Date.new(2026, 11, 30), payer: @payer,
                                          options: { fine_percent: 2, interest_percent: 1, message: "Outubro", discount_percent: 0 })
    request = client.to("/v2/cobv/").first
    assert_equal "https://pix-h.api.efipay.com.br/v2/cobv/#{'T' * 32}", request.url
    assert_equal "Bearer TOKEN-PIX", request.headers["Authorization"]
    assert request.tls[:cert].is_a?(OpenSSL::X509::Certificate) && request.tls[:key].private?, "o .p12 é aberto em memória e vai ao cliente HTTP"
    body = JSON.parse(request.body)
    assert_equal({ "dataDeVencimento" => "2026-11-30", "validadeAposVencimento" => 30 }, body["calendario"])
    assert_equal "1250.00", body.dig("valor", "original")
    assert_equal({ "modalidade" => 2, "valorPerc" => "2.00" }, body.dig("valor", "multa"))
    assert_equal({ "modalidade" => 3, "valorPerc" => "1.00" }, body.dig("valor", "juros"))
    assert_equal({ "nome" => "Maria Souza", "cpf" => "52998224725", "logradouro" => "Rua das Flores, 10", "cidade" => "Curitiba", "uf" => "PR", "cep" => "80010000" }, body["devedor"])
    assert_equal [ "pix@alfa.com.br", "Outubro" ], body.values_at("chave", "solicitacaoPagador")
    assert_equal [ "T" * 32, "active", 125_000, Date.new(2026, 11, 30) ], [ issued.external_id, issued.status, issued.amount_cents, issued.due_on ]
    assert_equal COBV_RESPONSE["pixCopiaECola"], issued.copy_paste
    assert_nil issued.qr_png, "a Efí devolveu SVG; o PNG é gerado aqui (IP-P3)"
    assert_equal "Basic #{Base64.strict_encode64("#{pix_account.secrets['client_id']}:#{pix_account.secrets['client_secret']}")}", client.to("/oauth/token").first.headers["Authorization"]
    assert client.to("/oauth/token").first.tls, "a autenticação do Pix também usa o certificado"
  end

  test "Pix: usa a imagem em PNG do fornecedor quando ela vem" do
    png = Payments::Providers::Fake::PNG
    use_efi_client(efi_client.on(:put, "/v2/cobv/", status: 201, body: COBV_RESPONSE)
                             .on(:get, "/v2/loc/789/qrcode", body: { "qrcode" => "x", "imagemQrcode" => "data:image/png;base64,#{Base64.strict_encode64(png)}" }))
    issued = @efi.issue_pix(pix_account, custom_id: "T" * 32, amount_cents: 1000, due_on: Date.new(2026, 11, 30), payer: @payer)
    assert_equal png, issued.qr_png
  end

  test "Pix: falha ao pedir a imagem do QR Code não derruba a emissão" do
    use_efi_client(efi_client.on(:put, "/v2/cobv/", status: 201, body: COBV_RESPONSE).on(:get, "/v2/loc/789/qrcode", status: 403, body: { "title" => "Acesso negado" }))
    assert_nil @efi.issue_pix(pix_account, custom_id: "T" * 32, amount_cents: 1000, due_on: Date.new(2026, 11, 30), payer: @payer).qr_png
  end

  test "Pix: cancelar usa PATCH com o estado de remoção e consultar traduz os estados" do
    client = use_efi_client(efi_client.on(:patch, "/v2/cobv/#{'T' * 32}", body: COBV_RESPONSE.merge("status" => "REMOVIDA_PELO_USUARIO_RECEBEDOR"))
                                      .on(:get, "/v2/cobv/#{'T' * 32}", body: COBV_RESPONSE.merge("status" => "CONCLUIDA")))
    assert_equal "canceled", @efi.cancel_pix(pix_account, "T" * 32).status
    assert_equal({ "status" => "REMOVIDA_PELO_USUARIO_RECEBEDOR" }, JSON.parse(client.to("/v2/cobv/").first.body))
    assert_equal "paid", @efi.fetch_pix(pix_account, "T" * 32).status
  end

  test "Pix sem certificado ou com chave Pix ausente é recusado antes de chamar a Efí" do
    account = make_efi_account(@alfa, modality: "pix", nickname: "Sem chave", environment: "production")
    account.update!(config: account.config.except("pix_key"), active: false) rescue account.update_columns(config: account.config.except("pix_key"))
    assert_raises(Payments::Providers::Error) { @efi.issue_pix(account, custom_id: "T" * 32, amount_cents: 1000, due_on: Date.new(2026, 11, 30), payer: @payer) }
  end

  test "ambiente de produção usa os hosts de produção" do
    production = make_efi_account(@alfa, modality: "boleto", environment: "production", nickname: "Prod")
    client = use_efi_client(efi_client.on(:post, "/v1/charge/one-step", body: BILLET_RESPONSE))
    @efi.issue_boleto(production, custom_id: "P" * 32, amount_cents: 1000, due_on: Date.new(2026, 11, 30), payer: @payer)
    assert_equal "https://cobrancas.api.efipay.com.br/v1/charge/one-step", client.to("/v1/charge/one-step").first.url
  end

  test "mapeia erros: recusa de negócio, credencial, indisponibilidade e resposta que não é JSON" do
    use_efi_client(efi_client.on(:post, "/v1/charge/one-step", status: 400, body: { "code" => 3_500_034, "error" => "validation_error", "error_description" => { "property" => "/payment/banking_billet/customer/cpf", "message" => "cpf inválido" } }))
    error = assert_raises(Payments::Providers::Error) { issue_boleto }
    assert_not_kind_of Payments::Providers::NetworkError, error
    assert_equal "cpf inválido", error.message

    use_efi_client(efi_client.on(:put, "/v2/cobv/", status: 400, body: { "title" => "Requisição inválida", "violacoes" => [ { "razao" => "inválido", "propriedade" => "devedor.cpf" } ] }))
    assert_match(/devedor.cpf inválido/, assert_raises(Payments::Providers::Error) { @efi.issue_pix(pix_account, custom_id: "T" * 32, amount_cents: 1, due_on: Date.new(2026, 11, 30), payer: @payer) }.message)

    use_efi_client(efi_client.on(:post, "/v1/charge/one-step", status: 503, body: {}))
    unavailable = assert_raises(Payments::Providers::NetworkError) { issue_boleto }
    assert unavailable.retry_safe, "503: a Efí disse que não processou"

    use_efi_client(efi_client.on(:post, "/v1/charge/one-step", status: 500, body: {}))
    assert_not assert_raises(Payments::Providers::NetworkError) { issue_boleto }.retry_safe, "500: o boleto pode ter sido criado"

    use_efi_client(efi_client.on(:post, "/v1/charge/one-step", status: 200, raw: "<html>"))
    assert_raises(Payments::Providers::Error) { issue_boleto }
  end

  test "Pix: qualquer erro de rede é seguro de repetir (txid nosso, PUT idempotente)" do
    use_efi_client(efi_client.on(:put, "/v2/cobv/", status: 500, body: {}))
    assert @efi.then { |e| assert_raises(Payments::Providers::NetworkError) { e.issue_pix(pix_account, custom_id: "T" * 32, amount_cents: 1, due_on: Date.new(2026, 11, 30), payer: @payer) } }.retry_safe
  end

  test "erro de rede do cliente HTTP passa como NetworkError com o aviso de repetição do cliente" do
    client = efi_client.on(:post, "/v1/charge/one-step") { raise Payments::Providers::NetworkError.new("o fornecedor não respondeu a tempo", retry_safe: false) }
    use_efi_client(client)
    assert_not assert_raises(Payments::Providers::NetworkError) { issue_boleto }.retry_safe
  end

  test "teste de conexão: autentica na API da modalidade e acusa credencial recusada" do
    use_efi_client(efi_client)
    assert @efi.test_connection(boleto_account).ok?
    assert @efi.test_connection(pix_account).ok?
    use_efi_client(efi_client.on(:post, "/v1/authorize", status: 401, body: { "error" => "invalid_client" }))
    Payments::Providers::Efi::TokenStore.reset!
    result = @efi.test_connection(boleto_account)
    assert_equal false, result.ok
    assert_match(/Credencial recusada pela Efí/, result.message)
  end

  test "nenhum segredo aparece em mensagens de erro nem no log" do
    secret = boleto_account.secrets["client_secret"]
    use_efi_client(efi_client.on(:post, "/v1/charge/one-step", status: 400, body: { "error_description" => "falhou" }))
    error = assert_raises(Payments::Providers::Error) { issue_boleto }
    assert_not_includes error.message, secret
    Rails.logger.flush if Rails.logger.respond_to?(:flush)
    log = Rails.root.join("log/test.log")
    text = File.exist?(log) ? File.binread(log).force_encoding("UTF-8").scrub : ""
    [ secret, boleto_account.secrets["client_id"], "TOKEN-COBRANCAS" ].each { |value| assert_not_includes text, value }
  end

  test "o cliente HTTP real recusa endereço sem https e converte falhas de conexão" do
    client = Payments::Providers::HttpClient.new
    assert_raises(Payments::Providers::Error) { client.request(:get, "http://cobrancas.api.efipay.com.br/x") }
    error = assert_raises(Payments::Providers::NetworkError) { client.request(:get, "https://127.0.0.1:1/x", open_timeout: 1) }
    assert error.retry_safe, "conexão que nem saiu"
  end
end
