require "test_helper"

# Página pública de pagamento (12, parte C, R277 a R280): sem login, pelo token. Cartão só por checkout transparente; boleto e Pix servidos daqui; 404 igual
# para qualquer link que não sirva; cabeçalhos de segurança; política de segurança de conteúdo restrita ao que o fornecedor declara; V10 por token.
class CheckoutsScreensTest < ActionDispatch::IntegrationTest
  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @customer = make_customer(@alfa)
    @checkout = make_checkout(customer: @customer, boleto: true, pix: true)
  end

  def page(checkout = @checkout) = Nokogiri::HTML5(response.body)

  def card_post(token = "token-aprovado-123456", installments: 1, checkout: @checkout, headers: {})
    post checkout_card_payment_path(checkout), params: { payment_token: token, installments: installments }, headers: headers
  end

  test "abre sem login: valor, Pix, boleto e cartão, com a forma em destaque primeiro (R277, R280)" do
    get checkout_path(@checkout)
    assert_response :success
    assert_select "h1", "Pagamento"
    assert_includes response.body, "R$ 999,00"
    assert_select "section h2", text: "Pix"
    assert_select "section h2", text: "Boleto"
    assert_select "section h2", text: "Cartão de crédito"
    assert_equal %w[Pix Boleto], page.css("section.cartao h2").map(&:text).first(2), "o Pix é o destaque"
    assert_select "textarea[readonly]#pix-copia-e-cola", text: /00020126/
    assert_select "input#boleto-linha-digitavel[readonly][value^='34191']"
  end

  test "mostra só o primeiro nome do pagador e nenhum documento (a página não vaza dados do pagador)" do
    get checkout_path(@checkout)
    assert_includes response.body, "Olá, Maria."
    assert_not_includes response.body, "Souza"
    assert_not_includes response.body, "52998224725"
    assert_not_includes response.body, "529.982"
  end

  test "cabeçalhos: sem cache, sem indexação, sem referenciador, permissões fechadas, não embutível (R277)" do
    get checkout_path(@checkout)
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "no-cache", response.headers["Pragma"]
    assert_equal "noindex, nofollow, noarchive", response.headers["X-Robots-Tag"]
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal "DENY", response.headers["X-Frame-Options"]
    assert_match(/camera=\(\)/, response.headers["Permissions-Policy"])
    assert_match(/payment=\(self\)/, response.headers["Permissions-Policy"])
    assert_select "meta[name=robots][content='noindex, nofollow, noarchive']"
  end

  test "a política de segurança de conteúdo da página: nada de fora, nem estilo embutido; script só com nonce (R278)" do
    get checkout_path(@checkout)
    csp = csp_of(response)
    assert_equal [ "'none'" ], csp["default-src"]
    assert_equal [ "'self'" ], csp["style-src"]
    assert_equal [ "'none'" ], csp["frame-src"]
    assert_equal [ "'none'" ], csp["object-src"]
    assert_equal [ "'none'" ], csp["frame-ancestors"]
    assert_equal [ "'none'" ], csp["base-uri"]
    assert_equal [ "'self'" ], csp["form-action"]
    assert_equal [ "'self'" ], csp["font-src"]
    assert_includes csp["script-src"], "'self'"
    assert(csp["script-src"].any? { |source| source.start_with?("'nonce-") })
    assert_not_includes csp["script-src"], "'unsafe-inline'"
    assert_not_includes csp["script-src"], "'unsafe-eval'"
    assert_equal [ "'self'", "ws://www.example.com" ], csp["connect-src"], "o fornecedor falso não declara domínio nenhum"
    nonce = csp["script-src"].grep(/nonce/).first[/'nonce-(.+)'/, 1]
    assert page.css("script[type=module], script[type=importmap]").all? { |script| script["nonce"] == nonce }
    assert page.css("script").none? { |script| script["src"].to_s.start_with?("http") }, "nenhum script de CDN"
  end

  test "o nonce muda a cada pedido" do
    nonces = 2.times.map { get(checkout_path(@checkout)); csp_of(response)["script-src"].grep(/nonce/).first }
    assert_not_equal nonces.first, nonces.last
  end

  test "com cartão da Efí, a política libera só os domínios que o adaptador declara, sem curinga e sem http (R278)" do
    tenant = @beta
    customer = make_customer(tenant, document: PaymentsHelper::JOAO, name: "João Pereira")
    make_efi_account(tenant, modality: "card", environment: "production")
    checkout = Payments::Checkouts.create(tenant: tenant, customer: customer, amount_cents: 5_000, card: true)
    get checkout_path(checkout)
    csp = csp_of(response)
    assert_response :success
    assert_equal [ "'self'", "https://device.clearsale.com.br" ], csp["script-src"].reject { |s| s.start_with?("'nonce-") }
    expected = %w[https://tokenizer.sejaefi.com.br https://cobrancas.api.efipay.com.br https://device.clearsale.com.br https://web.fpcs-monitor.com.br]
    assert_equal expected.sort, (csp["connect-src"] - [ "'self'", "ws://www.example.com" ]).sort
    csp.values.flatten.each { |source| assert_no_match(/\*|\Ahttp:/, source) }
    assert_select "form[data-driver='payments/drivers/efi'][data-script='payment-token-efi']"
    assert_includes page.at_css("form[data-cartao]")["data-config"], "ac0123456789abcdef"
  end

  test "em homologação a Efí libera também a API de cobranças de homologação" do
    make_efi_account(@beta, modality: "card", environment: "sandbox")
    checkout = Payments::Checkouts.create(tenant: @beta, customer: make_customer(@beta, document: PaymentsHelper::JOAO, name: "João"), amount_cents: 5_000, environment: "sandbox")
    get checkout_path(checkout)
    assert_includes csp_of(response)["connect-src"], "https://cobrancas-h.api.efipay.com.br"
  end

  test "link sem cartão não libera domínio de fornecedor nenhum" do
    only_pix = Payments::Checkouts.create(tenant: @alfa, customer: @customer, instruments: [ @checkout.instruments.find_by(kind: "pix") ].tap { |i| i.first.update_columns(checkout_id: nil) }, card: false)
    get checkout_path(only_pix)
    assert_equal [ "'self'", "ws://www.example.com" ], csp_of(response)["connect-src"]
    assert_select "form[data-cartao]", false
  end

  test "os campos do cartão não têm atributo name: o formulário só envia payment_token e parcelas (R278)" do
    get checkout_path(@checkout)
    form = page.at_css("form[data-cartao]")
    named = form.css("[name]").map { |field| field["name"] }
    assert_equal %w[installments payment_token], named.sort
    card_inputs = form.css("#cartao-numero, #cartao-titular, #cartao-validade, #cartao-codigo")
    assert_equal 4, card_inputs.size
    assert card_inputs.none? { |input| input.key?("name") }
    assert_equal "cc-number", form.at_css("#cartao-numero")["autocomplete"]
    assert_equal "password", form.at_css("#cartao-codigo")["type"]
    assert_equal "", form.at_css("#payment-token")["value"].to_s
  end

  test "a página não tem link do fornecedor nem redireciona a ele (R279)" do
    get checkout_path(@checkout)
    assert_no_match(%r{gerencianet|efipay|sejaefi|FAKE-}, response.body)
    links = page.css("a[href]").map { |a| a["href"] }
    assert links.all? { |href| href.start_with?("/") || href.start_with?("#") }, links.inspect
    assert_select "img[src^='/pagar/']"
    get checkout_boleto_path(@checkout)
    assert_nil response.headers["Location"]
    get checkout_qr_code_path(@checkout)
    assert_nil response.headers["Location"]
  end

  test "o PDF do boleto e o QR Code do Pix saem daqui, conferidos pelo SHA-256, sem cache (R279)" do
    get checkout_boleto_path(@checkout)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_equal @checkout.instruments.find_by(kind: "boleto").boleto_pdf.download, response.body.b
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "noindex, nofollow, noarchive", response.headers["X-Robots-Tag"]
    get checkout_qr_code_path(@checkout)
    assert_response :success
    assert_equal "image/png", response.media_type
    assert response.body.b.start_with?("\x89PNG".b)
  end

  test "arquivo adulterado no disco (SHA-256 diferente) não é servido" do
    @checkout.instruments.find_by(kind: "boleto").update_columns(boleto_pdf_sha256: "0" * 64)
    get checkout_boleto_path(@checkout)
    assert_response :not_found
  end

  test "link sem boleto ou sem Pix responde 404 nos arquivos" do
    only_card = make_checkout(customer: @customer)
    get checkout_boleto_path(only_card)
    assert_response :not_found
    get checkout_qr_code_path(only_card)
    assert_response :not_found
  end

  test "404 igual para qualquer erro: token inexistente, de formato estranho, vencido ou cancelado (R277)" do
    expired = make_checkout(customer: @customer, expires_at: 1.second.from_now)
    expired.update_columns(expires_at: 1.minute.ago)
    canceled = make_checkout(customer: @customer)
    canceled.update_columns(state: "canceled")
    bodies = [ "nao-existe", "x" * 43, "com.ponto", "a%2Fb", expired.token, canceled.token ].map do |token|
      get "/pagar/#{token}"
      assert_response :not_found, token
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_equal "noindex, nofollow, noarchive", response.headers["X-Robots-Tag"]
      assert_equal [ "'none'" ], csp_of(response)["default-src"]
      response.body.gsub(/nonce="[^"]+"/, "").gsub(/csrf-token" content="[^"]+"/, "")
    end
    assert_equal 1, bodies.uniq.size, "o corpo é o mesmo para qualquer motivo"
    assert_includes bodies.first, "não está disponível"
    [ checkout_boleto_path(token: expired.token), checkout_qr_code_path(token: expired.token), checkout_situation_path(token: canceled.token), checkout_installments_path(token: expired.token) ].each do |path|
      get path
      assert_response :not_found
    end
    post checkout_card_payment_path(token: expired.token), params: { payment_token: "token-aprovado-123456", installments: 1 }
    assert_response :not_found
    assert_equal 0, PaymentInstrument.where(kind: "card").count
  end

  test "o link vencido deixa de abrir na hora e o renovado volta a abrir" do
    @checkout.update_columns(expires_at: 1.minute.ago)
    get checkout_path(@checkout)
    assert_response :not_found
    Payments::Checkouts.renew(@checkout, days: 5)
    get checkout_path(@checkout)
    assert_response :success
  end

  test "o contador de acessos conta a página, não os arquivos nem os trechos" do
    3.times { get checkout_path(@checkout) }
    get checkout_boleto_path(@checkout)
    get checkout_situation_path(@checkout)
    assert_equal 3, @checkout.reload.access_count
    assert_not_nil @checkout.last_accessed_at
  end

  test "V10 por token: o link de um credor nunca mostra nem serve dado de outro" do
    beta_customer = make_customer(@beta, document: PaymentsHelper::JOAO, name: "João Pereira")
    beta_checkout = make_checkout(tenant: @beta, customer: beta_customer, pix: true, amount_cents: 12_345)
    get checkout_path(beta_checkout)
    assert_response :success
    assert_includes response.body, "R$ 123,45"
    assert_not_includes response.body, "R$ 999,00"
    assert_not_includes response.body, "Maria"
    get checkout_path(@checkout)
    assert_not_includes response.body, "João"
    assert_not_includes response.body, "R$ 123,45"
    assert_select "header strong", text: @alfa.display_name
    # O QR Code do link de um credor é o do instrumento dele.
    get checkout_qr_code_path(beta_checkout)
    assert_equal beta_checkout.instruments.find_by(kind: "pix").pix_qr_png.download, response.body.b
    get checkout_qr_code_path(@checkout)
    assert_equal @checkout.instruments.find_by(kind: "pix").pix_qr_png.download, response.body.b
  end

  test "boleto vencido continua na página até days_to_write_off, com o valor emitido, e some depois (R280)" do
    boleto = @checkout.instruments.find_by(kind: "boleto")
    boleto.update_columns(due_on: Date.current - 10, state: "expired")
    get checkout_path(@checkout)
    assert_select "section h2", text: "Boleto"
    assert_includes response.body, "venceu em #{(Date.current - 10).strftime('%d/%m/%Y')}"
    assert_includes response.body, "R$ 999,00"
    boleto.update_columns(due_on: Date.current - 40)
    get checkout_path(@checkout)
    assert_select "section h2", text: "Boleto", count: 0
  end

  test "pago, aprovado e não confirmado mostram só o aviso, sem formas de pagar" do
    { "paid" => "Pagamento confirmado", "card_approved" => "aprovado", "card_unconfirmed" => "Não conseguimos confirmar" }.each do |state, text|
      @checkout.update_columns(state: state)
      get checkout_path(@checkout)
      assert_includes response.body, text
      assert_select "form[data-cartao]", false
      assert_select "section.cartao", false
    end
  end

  test "pagar no cartão: só payment_token e parcelas; o resultado volta na resposta e o link passa a aprovado (R278)" do
    assert_difference -> { PaymentInstrument.where(kind: "card").count }, 1 do
      card_post(installments: 3)
    end
    assert_response :success
    assert_includes response.body, "Pagamento no cartão aprovado"
    assert_select "#opcoes[hx-get$='/situacao']"
    assert @checkout.reload.state_card_approved?
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "recusa do cartão: mensagem em pt-BR por código, sem o texto do fornecedor; o formulário volta" do
    { "recusado" => [ "não autorizou o pagamento por segurança", "use outro cartão" ], "tente-depois" => [ "não pôde ser autorizado agora", "tentar de novo" ],
      "dados-invalidos" => [ "dados do cartão não foram aceitos", "tentar de novo" ] }.each do |token, texts|
      card_post(token)
      assert_response :success
      texts.each { |text| assert_includes response.body, text }
      assert_no_match(/Recusa simulada/, response.body)
      assert_select "form[data-cartao]"
      assert_select "[role=alert]", minimum: 1
    end
  end

  test "clique duplo e retentativa: o mesmo token cobra uma vez só" do
    2.times { card_post("token-duplo-123456") }
    assert_equal 1, PaymentInstrument.where(kind: "card").count
    assert_equal 1, Payments::Providers::Fake.store[:instruments].values.count { |i| i[:kind] == "card" }
  end

  test "pedido sem payment_token ou com parcelas demais: 422 com a mensagem, nada cobrado" do
    post checkout_card_payment_path(@checkout), params: { installments: 1 }
    assert_response :unprocessable_content
    card_post("token-aprovado-123456", installments: 99)
    assert_response :unprocessable_content
    assert_equal 0, PaymentInstrument.where(kind: "card").count
  end

  test "os dados do cartão enviados por engano nunca chegam à cobrança nem ao log: o servidor só lê payment_token e installments" do
    secret_number = "4111111111111111"
    post checkout_card_payment_path(@checkout), params: { payment_token: "token-aprovado-123456", installments: 1, number: secret_number, cvv: "123" }
    assert_response :success
    assert_not_includes PaymentInstrument.where(kind: "card").first.attributes.to_json, secret_number
    log = File.read(Rails.root.join("log/test.log")).last(400_000)
    assert_not_includes log, "token-aprovado-123456", "o payment_token é filtrado do log"
    assert_not_includes log, secret_number
  end

  test "sem o token de formulário o POST do cartão é recusado com a página vencida e nada é cobrado" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    card_post
    assert_response :unprocessable_content
    assert_includes response.body, "Atualize a página"
    assert_equal 0, PaymentInstrument.where(kind: "card").count
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "as parcelas pela bandeira: o adaptador dá as opções, limitadas ao máximo da conta; só a bandeira chega" do
    get checkout_installments_path(@checkout, brand: "visa")
    assert_response :success
    assert_select "select#cartao-parcelas[name=installments] option", 6
    assert_select "option[value='1']", text: "1x de R$ 999,00"
    assert_select "option[value='3']", text: "3x de R$ 333,00"
    get checkout_installments_path(@checkout)
    assert_response :success
  end

  test "o trecho de situação reflete o estado atual (a página o busca quando o canal avisa)" do
    get checkout_situation_path(@checkout)
    assert_select "form[data-cartao]"
    @checkout.update_columns(state: "paid")
    get checkout_situation_path(@checkout)
    assert_includes response.body, "Pagamento confirmado"
    assert_select "form[data-cartao]", false
  end

  test "limite de requisições por IP na página (429)" do
    121.times { get checkout_path(@checkout) }
    assert_response :too_many_requests
  end

  test "limite de tentativas de cartão por IP (429), contra teste de cartões" do
    10.times { |i| card_post("token-recusado-#{i}-123456", installments: 1) }
    card_post("token-onze-123456")
    assert_response :too_many_requests
    assert_equal 1, PaymentInstrument.where(kind: "card").count, "a primeira aprovou; as outras só devolveram o resultado; a 11ª nem chegou"
  end

  test "a página não pede login e não cria sessão do sistema" do
    get checkout_path(@checkout)
    assert_response :success
    assert_nil cookies[:session_id]
    assert_no_match(%r{Sair|Trocar a senha}, response.body)
  end
end
