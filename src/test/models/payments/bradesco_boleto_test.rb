require "test_helper"

# Boleto do Bradesco (12, revisão 4) com respostas gravadas a partir do manual "API de Cobrança" 1.6.4 e uma autenticação de teste no lugar da que o
# manual não traz (bloqueio B1): nosso número reservado pelo CRM, registro com o texto do pagador adaptado, "título já cadastrado" na repetição, ficha
# gerada aqui, consulta, baixa, alteração, janela da madrugada, aviso e lista de liquidados com o mesmo identificador. Nenhum teste chama o Bradesco.
class PaymentsBradescoBoletoTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    # O boleto do Bradesco não sai das 0h às 3h (R284h): o relógio fica às 10h do dia, senão os testes falham quando rodam de madrugada.
    travel_to Time.current.change(hour: 10)
    @alfa = tenants(:alfa)
    @bradesco = Payments::Providers::Bradesco.new
    Payments::Providers::Bradesco.boleto_auth = BradescoHttpHelper::TestBoletoAuth.new
    @payer = { name: "João José da Silva", document: "11438390807",
               address: { "street" => "R. das Flores", "number" => "10", "complement" => "apto 3", "district" => "Alphaville", "city" => "Barueri", "state" => "SP", "zip" => "06050040" } }
  end

  def account = (@account ||= make_bradesco_account(@alfa, modality: "boleto", environment: "production"))

  # Linha digitável coerente com a integração do teste (agência 2856, carteira 09, conta 0222652), o nosso número, o vencimento e o valor.
  def line_for(our_number, due_on, amount_cents)
    free = "2856" + "09" + our_number.to_s.rjust(11, "0") + "0222652" + "0"
    body = "2379" + Payments::Febraban.due_factor(due_on).to_s + amount_cents.to_s.rjust(10, "0") + free
    Payments::Febraban.digitable_from_barcode(body[0, 4] + Payments::Febraban.barcode_check_digit(body).to_s + body[4..])
  end

  def registration_response(our_number, due_on, amount_cents)
    { "idProduto" => 9, "negociacao" => 285_600_000_000_222_652, "nuTituloGerado" => our_number.to_i, "codStatus10" => 1, "status10" => "A VENCER/VENCIDO",
      "nomePagador" => "JOAO JOSE DA SILVA", "seuNumeroTitulo" => "X", "dtRegistro" => "14112026", "especieDocumentoTitulo" => "ME",
      "dtVencimento" => due_on.strftime("%d.%m.%Y"), "vlTitulo" => amount_cents, "linhaDigitavel" => line_for(our_number, due_on, amount_cents) }
  end

  def lookup_response(our_number, due_on, amount_cents, status: 1, paid: 0.0, paid_on: 0)
    { "status" => 200, "transacao" => "CBTTIAGS", "mensagem" => "CONSULTA EFETUADA",
      "titulo" => { "codStatus" => status, "status" => "X", "snumero" => "X", "dataVencto" => due_on.strftime("%d/%m/%Y"), "valMoeda" => amount_cents, "qtdeCas" => 2,
                    "linhaDig" => line_for(our_number, due_on, amount_cents), "dtPagto" => paid_on, "vlrPagto" => paid } }
  end

  def emit_boleto(amount_cents: 125_599, due_on: Date.current + 10)
    account
    bill = make_bill(@alfa, number: "NF-#{SecureRandom.hex(2)}", amount_cents: amount_cents, document: "11438390807", name: "João José da Silva")
    add_address(bill.customer, @payer[:address].transform_keys(&:to_sym)) unless bill.customer.contacts.any?(&:address?)
    Payments::Issuer.new.request(tenant: @alfa, kind: "boleto", amount_cents: amount_cents, customer: bill.customer, due_on: due_on, object: bill, environment: "production")
  end

  def bank_answering(due_on, amount_cents, registration: nil)
    numbers = []
    client = bradesco_client.on(:post, "/boleto/cobranca-registro/v1/cobranca") do |request|
      body = JSON.parse(request.body)
      numbers << body["nuTitulo"]
      registration ? registration.call(body) : { status: 200, body: registration_response(body["nuTitulo"], due_on, amount_cents) }
    end
    client.on(:post, "/boleto/cobranca-consulta/v1/consultar") { |request| { status: 200, body: lookup_response(JSON.parse(request.body)["nossoNumero"], due_on, amount_cents) } }
    [ use_bradesco_client(client), numbers ]
  end

  test "sem a autenticação da API de cobrança, nada sai e o fornecedor não oferece boleto (R284j)" do
    Payments::Providers::Bradesco.boleto_auth = nil
    client = use_bradesco_client(bradesco_client)
    error = assert_raises(Payments::Providers::Error) { @bradesco.fetch_boleto(account_without_auth, "52280000492") }
    assert_includes error.message, "Autenticação do boleto do Bradesco não configurada"
    assert_empty client.requests
    assert_not_includes Payments::Providers.for_modality("boleto"), "bradesco"
  end

  test "registro: corpo do manual, negociação de 18, nosso número reservado, texto sem acento nem pontuação e cortado (R284f, R284i; C l. 262-1182)" do
    due_on = Date.current + 10
    client, numbers = bank_answering(due_on, 125_599)
    instrument = emit_boleto(due_on: due_on)
    perform_enqueued_jobs
    instrument.reload
    assert instrument.state_active?, instrument.failure_reason
    body = JSON.parse(client.to("/cobranca-registro/").first.body)
    assert_equal [ 41_755_489, 1, 55, 9, 285_600_000_000_222_652 ], body.values_at("nuCPFCNPJ", "filialCPFCNPJ", "ctrlCPFCNPJ", "idProduto", "nuNegociacao")
    assert_equal [ 52_280_000_490 ], numbers
    assert_equal [ "52280000490", "52280000490" ], [ instrument.our_number, instrument.external_id ]
    assert_equal instrument.custom_id.last(15), body["nuCliente"]
    assert_equal [ Date.current.strftime("%d.%m.%Y"), due_on.strftime("%d.%m.%Y"), 1255.99, 21 ], body.values_at("dtEmissaoTitulo", "dtVencimentoTitulo", "vlNominalTitulo", "cdEspecieTitulo")
    assert_equal [ "JOAO JOSE DA SILVA", "R DAS FLORES", "10", "APTO 3", "ALPHAVILLE", "BARUERI", "SP", 6050, 40 ],
                 body.values_at("nomePagador", "logradouroPagador", "nuLogradouroPagador", "complementoLogradouroPagador", "bairroPagador", "municipioPagador", "ufPagador", "cepPagador", "complementoCepPagador")
    assert_equal [ 1, 11_438_390_807 ], body.values_at("cdIndCpfcnpjPagador", "nuCpfcnpjPagador")
    assert_equal [ 2.0, 1, 1.0, 1, 30 ], body.values_at("percentualMulta", "qtdeDiasMulta", "percentualJuros", "qtdeDiasJuros", "tipoPrazoDecursoTres")
    assert_match %r{\APOST /boleto/cobranca-registro/v1/cobranca \h{8}\z}, client.to("/cobranca-registro/").first.headers["X-Autenticacao-De-Teste"]
    assert_equal "João José da Silva", instrument.payer_name, "o instrumento guarda o pagador como veio"
  end

  test "a ficha gerada é guardada com SHA-256 conferido e tem o código de barras da linha do banco (R284e, R273)" do
    due_on = Date.current + 10
    bank_answering(due_on, 125_599)
    instrument = emit_boleto(due_on: due_on)
    perform_enqueued_jobs
    instrument.reload
    assert instrument.boleto_pdf.attached?
    pdf = Payments::InstrumentReader.new(instrument).pdf
    assert pdf.start_with?("%PDF")
    assert_equal line_for("52280000490", due_on, 125_599), instrument.digitable_line
    assert_includes pdf.b, "re\nf".b
  end

  test "linha digitável que não fecha com o título faz o instrumento falhar sem ficha (R284e)" do
    due_on = Date.current + 10
    client, _numbers = bank_answering(due_on, 125_599)
    client.on(:post, "/boleto/cobranca-consulta/v1/consultar") { |request| { status: 200, body: lookup_response(JSON.parse(request.body)["nossoNumero"], due_on + 1, 125_599) } }
    instrument = emit_boleto(due_on: due_on)
    perform_enqueued_jobs
    instrument.reload
    assert instrument.state_failed?
    assert_includes instrument.failure_reason, "fator de vencimento"
    assert_not instrument.boleto_pdf.attached?
  end

  test "nosso número: três reservas seguidas são diferentes, e o número inicial aumentado é respeitado (R284f)" do
    due_on = Date.current + 10
    _client, numbers = bank_answering(due_on, 125_599)
    3.times { emit_boleto(due_on: due_on) }
    perform_enqueued_jobs
    assert_equal [ 52_280_000_490, 52_280_000_491, 52_280_000_492 ], numbers.sort
    account.update!(config: account.config.merge("our_number_start" => 52_280_001_000))
    emit_boleto(due_on: due_on)
    perform_enqueued_jobs
    assert_equal 52_280_001_000, numbers.last
    assert_equal 52_280_001_000, account.reload.our_number_last
  end

  test "tempo esgotado ao ler a resposta: repete com o mesmo número, 69 consulta e segue (R284f, R276a item 4)" do
    due_on = Date.current + 10
    attempt = 0
    _client, numbers = bank_answering(due_on, 125_599, registration: lambda do |_body|
      attempt += 1
      raise Payments::Providers::NetworkError.new("o fornecedor não respondeu a tempo", retry_safe: false) if attempt == 1

      { status: 200, body: { "codigo" => 69, "mensagem" => "Título já cadastrado" } }
    end)
    instrument = emit_boleto(due_on: due_on)
    assert_raises(Payments::Providers::NetworkError) { Payments::Issuer.new.perform(instrument.reload) }
    assert instrument.reload.state_emitting?, "o boleto com número reservado repete, como o Pix"
    Payments::Issuer.new.perform(instrument)
    instrument.reload
    assert instrument.state_active?, instrument.failure_reason
    assert_equal [ 52_280_000_490, 52_280_000_490 ], numbers
  end

  test "69 com um título diferente no mesmo número: o instrumento falha e não adota o título de outro (R284f)" do
    due_on = Date.current + 10
    client, _numbers = bank_answering(due_on, 125_599, registration: ->(_body) { { status: 200, body: { "mensagem" => "69 - Título já cadastrado" }, headers: { "Status-Header" => "69" } } })
    client.on(:post, "/boleto/cobranca-consulta/v1/consultar") { |request| { status: 200, body: lookup_response(JSON.parse(request.body)["nossoNumero"], due_on, 99_900) } }
    instrument = emit_boleto(due_on: due_on)
    perform_enqueued_jobs
    instrument.reload
    assert instrument.state_failed?
    assert_includes instrument.failure_reason, "já está num título diferente"
  end

  test "indisponibilidade do registro (-99) e 503 repetem; recusa de conteúdo não (C l. 1502-1700)" do
    [ { status: 200, body: { "codigo" => -99, "mensagem" => "Serviço indisponível" } }, { status: 503, body: {} } ].each do |answer|
      use_bradesco_client(bradesco_client.on(:post, "/cobranca-registro/", **answer))
      error = assert_raises(Payments::Providers::NetworkError) { @bradesco.issue_boleto(account, custom_id: "C" * 32, amount_cents: 100, due_on: Date.current + 5, payer: @payer, options: { our_number: "1" }) }
      assert error.retry_safe
    end
    use_bradesco_client(bradesco_client.on(:post, "/cobranca-registro/", body: { "codigo" => 23, "mensagem" => "Seu Número Inválido" }))
    error = assert_raises(Payments::Providers::Error) { @bradesco.issue_boleto(account, custom_id: "C" * 32, amount_cents: 100, due_on: Date.current + 5, payer: @payer, options: { our_number: "1" }) }
    assert_not_kind_of Payments::Providers::NetworkError, error
    assert_includes error.message, "Seu Número Inválido"
  end

  test "pagador sem endereço não se registra; sem número vai SN (R284i)" do
    use_bradesco_client(bradesco_client)
    assert_raises(Payments::Providers::Error) { @bradesco.issue_boleto(account, custom_id: "C" * 32, amount_cents: 100, due_on: Date.current + 5, payer: @payer.merge(address: {}), options: { our_number: "1" }) }
    body = Payments::Providers::Bradesco::Payloads.registration_body(account, our_number: "1", custom_id: "C" * 32, amount_cents: 100, due_on: Date.current + 5,
                                                                     payer: @payer.merge(address: @payer[:address].merge("number" => "")), options: {})
    assert_equal "SN", body["nuLogradouroPagador"]
  end

  test "consulta no nosso vocabulário: pago (61) com o valor pago, baixado (57), vencido por decurso (53), a vencer (01) (C l. 3443-3567)" do
    due_on = Date.new(2026, 12, 1)
    { 61 => "paid", 13 => "paid", 57 => "canceled", 53 => "expired", 1 => "active", 56 => "active" }.each do |code, status|
      use_bradesco_client(bradesco_client.on(:post, "/cobranca-consulta/", body: lookup_response("52280000492", due_on, 125_599, status: code, paid: (code == 61 ? 1255.99 : 0.0))))
      issued = @bradesco.fetch_boleto(account, "52280000492")
      assert_equal status, issued.status, "código #{code}"
      assert_equal 125_599, issued.paid_cents if code == 61
    end
  end

  test "baixa com o código 57; repetida, a consulta que mostra baixado é aceita (C l. 2148-2255)" do
    client = use_bradesco_client(bradesco_client.on(:post, "/cobranca-baixa/", body: { "status" => 200, "transacao" => "CBTTIAGQ", "mensagem" => "CBTT0532 - SOLICITACAO DE BAIXA EFETUADA" }))
    assert_equal "canceled", @bradesco.cancel_boleto(account, "52280000492").status
    assert_equal({ "cpfCnpj" => { "cpfCnpj" => 41_755_489, "filial" => 1, "controle" => 55 }, "produto" => 9, "negociacao" => 28_560_222_652, "nossoNumero" => 52_280_000_492,
                   "sequencia" => 0, "codigoBaixa" => 57 }, JSON.parse(client.to("/cobranca-baixa/").first.body))
    use_bradesco_client(bradesco_client.on(:post, "/cobranca-baixa/", body: { "status" => 412, "causa" => "CBTT0931 - STATUS DO TITULO INVALIDO" })
                                       .on(:post, "/cobranca-consulta/", body: lookup_response("52280000492", Date.new(2026, 12, 1), 125_599, status: 57)))
    assert_equal "canceled", @bradesco.cancel_boleto(account, "52280000492").status
  end

  test "mudar o vencimento: PUT de alteração, consulta da linha nova e a ficha refeita (C l. 2344-2665)" do
    due_on = Date.current + 10
    new_due = Date.current + 20
    client, _numbers = bank_answering(due_on, 125_599)
    instrument = emit_boleto(due_on: due_on)
    perform_enqueued_jobs
    client.on(:put, "/cobranca-altera/", body: { "status" => 200, "transacao" => "CBTTIAGP", "mensagem" => "CBTT0445 - ALTERACAO EFETUADA" })
    client.on(:post, "/cobranca-consulta/") { |request| { status: 200, body: lookup_response(JSON.parse(request.body)["nossoNumero"], new_due, 125_599) } }
    Payments::Issuer.new.change_due_date(instrument.reload, new_due)
    body = JSON.parse(client.to("/cobranca-altera/").first.body)
    assert_equal({ "dataVencimento" => new_due.strftime("%d%m%Y").to_i, "tipoVencimento" => 0 }, body.dig("dadosTitulo", "vencimento"))
    assert_equal new_due, instrument.reload.due_on
    assert instrument.boleto_pdf.attached?
  end

  test "na janela das 00h às 03h a emissão não chama o banco e volta às 03h05 sem contar tentativa (R284h)" do
    client = use_bradesco_client(bradesco_client)
    travel_to Time.zone.parse("2026-11-16 01:00") do
      instrument = emit_boleto(due_on: Date.new(2026, 11, 30))
      clear_enqueued_jobs
      Payments::Issuer.new.perform(instrument)
      assert_equal 0, instrument.reload.attempts
      job = enqueued_jobs.find { |queued| queued["job_class"] == "IssueInstrumentJob" }
      assert_equal Time.zone.parse("2026-11-16 03:05"), Time.zone.parse(job["scheduled_at"])
      assert_raises(Payments::Issuer::Refused) { Payments::Issuer.new.change_due_date(instrument, Date.new(2026, 12, 5)) } if instrument.state_active?
      assert_nil Payments::PaidList.new(account).call
    end
    assert_empty client.requests
  end

  test "aviso de pagamento e lista de liquidados dão o mesmo identificador para o mesmo pagamento (R284b; C l. 3978-4016, 6736-6790)" do
    secret = account.rotate_webhook_secret!
    webhook = { "tipoEvento" => "P", "produto" => "09", "negociacao" => "28560222652", "nossoNumero" => "52280000492", "dataRegistro" => "2026-11-10",
                "dataVencimento" => "2026-11-30", "valorBoleto" => "0000000001255.99", "bancoRecebedor" => "237", "canalPagamento" => "3", "dataPagamento" => "2026-11-13",
                "horaPagamento" => "101508", "valorPagamento" => "0000000001255.99" }.to_json
    from_webhook = @bradesco.parse_notification(account, body: webhook, headers: {}, context: { query: { "hmac" => Payments::WebhookUrl.token(account, secret) } }).sole
    assert_raises(Payments::Providers::InvalidSignature) { @bradesco.parse_notification(account, body: webhook, headers: {}, context: { query: { "hmac" => "x" } }) }

    pages = [ { "status" => 200, "pagina" => 1, "indMaisPagina" => "S", "titulos" => [ { "nossoNumero" => 52_280_000_492, "digitoNossoNumero" => "5", "dataPagamento" => 13_112_026, "valorPagamento" => 125_599 } ] },
              { "status" => 200, "pagina" => 2, "indMaisPagina" => "N", "titulos" => [ { "nossoNumero" => 52_280_000_493, "dataPagamento" => 13_112_026, "valorPagamento" => 5_000 } ] } ]
    client = use_bradesco_client(bradesco_client.on(:post, "/cobranca-lista/") { |request| { status: 200, body: pages[JSON.parse(request.body)["paginaAnterior"].zero? ? 0 : 1] } })
    from_list = @bradesco.list_paid(account, from: Time.zone.parse("2026-11-13 06:20"), to: Time.zone.parse("2026-11-14 07:20"))
    assert_equal [ from_webhook.event_id, "boleto:52280000493:2026-11-13:5000" ], from_list.map(&:event_id)
    assert_equal "boleto:52280000492:2026-11-13:125599", from_webhook.event_id
    assert_equal [ 125_599, "52280000492" ], [ from_webhook.amount_cents, from_webhook.external_id ]
    bodies = client.to("/cobranca-lista/").map { |request| JSON.parse(request.body) }
    assert_equal [ 0, 1 ], bodies.map { |body| body["paginaAnterior"] }
    assert_equal [ 13_112_026, 14_112_026 ], bodies.first.values_at("dataPagamentoDe", "dataPagamentoAte")
  end

  test "boleto pago pelo aviso e depois na lista do dia seguinte: um aviso, um pagamento (R284b)" do
    due_on = Date.current + 10
    client, _numbers = bank_answering(due_on, 125_599)
    instrument = emit_boleto(due_on: due_on)
    perform_enqueued_jobs
    instrument.reload
    client.on(:post, "/cobranca-consulta/") { |request| { status: 200, body: lookup_response(JSON.parse(request.body)["nossoNumero"], due_on, 125_599, status: 61, paid: 1255.99, paid_on: Date.current.strftime("%d%m%Y").to_i) } }
    secret = account.rotate_webhook_secret!
    body = { "tipoEvento" => "P", "nossoNumero" => instrument.our_number, "dataPagamento" => Date.current.iso8601, "horaPagamento" => "090000", "valorPagamento" => "1255.99" }.to_json
    notification = @bradesco.parse_notification(account, body: body, headers: {}, context: { query: { "hmac" => Payments::WebhookUrl.token(account, secret) } }).sole
    event, _queue = PaymentEvent.record(account, notification)
    perform_enqueued_jobs { ProcessPaymentEventJob.perform_later(event) }
    assert instrument.reload.state_paid?
    client.on(:post, "/cobranca-lista/", body: { "status" => 200, "indMaisPagina" => "N", "titulos" => [ { "nossoNumero" => instrument.our_number.to_i, "dataPagamento" => Date.current.strftime("%d%m%Y").to_i, "valorPagamento" => 125_599 } ] })
    travel_to(Time.zone.parse("#{Date.current + 1} 07:20")) { Payments::PaidList.new(account.reload).call }
    assert_equal [ 1, 1 ], [ PaymentEvent.where(account: account).count, Payment.count ]
  end

  test "teste de conexão: consultar um nosso número que não existe e receber 'título inexistente' prova a autenticação (C l. 2289-2322)" do
    use_bradesco_client(bradesco_client.on(:post, "/cobranca-consulta/", status: 200, body: { "status" => 412, "causa" => "CBTT0552 - TITULO INEXISTENTE PARA O CONTRATO" }))
    assert Payments::AccountTester.new.call(account).ok?
    use_bradesco_client(bradesco_client.on(:post, "/cobranca-consulta/", status: 403, body: { "mensagem" => "CBTT0403 - USUARIO NAO AUTORIZADO" }))
    assert_not Payments::AccountTester.new.call(account).ok?
  end

  test "cadastro do webhook de boleto: URL de até 100, inclusão com aviso de pagamento (C l. 6466-6626; R284g)" do
    account.rotate_webhook_secret!
    client = use_bradesco_client(bradesco_client.on(:post, "/cobranca-webhook/v1/executar", body: { "utilizaWebhook" => "S", "urlEnvio" => "x", "datahoraAtualizacao" => "2026-11-14T10:00:00-03:00" }))
    with_config(public_url: "https://crm.areacli.com") do
      url = Payments::WebhookRegistration.new(account).call
      body = JSON.parse(client.to("/cobranca-webhook/").first.body)
      assert_equal [ "I", "S", url, "1", "1" ], body.values_at("tipoCadastro", "utilizaWebhook", "urlEnvio", "tipoAviso", "versaoLayout")
      assert_equal({ "cpfCnpj" => "41755489", "filial" => "1", "controle" => "55" }, body["documento"])
      assert_operator url.length, :<=, 100
    end
    with_config(public_url: "https://crm.areacli.com/um/caminho/muito/comprido/para/caber/no/cadastro") do
      assert_raises(Payments::Providers::Error) { Payments::WebhookRegistration.new(account).call }
    end
  end

  private
    # Integração criada enquanto a autenticação de teste existe e lida depois, sem ela.
    def account_without_auth
      Payments::Providers::Bradesco.boleto_auth = BradescoHttpHelper::TestBoletoAuth.new
      created = make_bradesco_account(@alfa, modality: "boleto", nickname: "Boleto sem autenticação")
      Payments::Providers::Bradesco.boleto_auth = nil
      created
    end
end
