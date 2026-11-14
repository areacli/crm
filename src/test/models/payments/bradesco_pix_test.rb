require "test_helper"

# Pix do Bradesco (12, revisão 4) com respostas gravadas a partir do manual "API Pix Recebimento" 2.6.1, versão 08: token por formulário com Basic e
# mTLS, `cobv-emv` com a resposta embrulhada, 412 do txid em uso, consulta com 204 e `horário` acentuado, cancelamento só com o estado, devolução,
# aviso pelo webhook e lista de recebidos com o mesmo identificador. Nenhum teste chama o Bradesco.
class PaymentsBradescoPixTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  TXID = "APIPixBradesco000000000000000000009".freeze
  E2E = "E60746948202611141000A1B2C3D4E5F6G".freeze
  COBV = { "calendario" => { "criacao" => "2026-11-14T10:00:00Z", "dataDeVencimento" => "2026-11-30", "validadeAposVencimento" => 30 }, "txid" => TXID, "revisao" => 0,
           "loc" => { "id" => 1234, "location" => "qrpix-h.bradesco.com.br/qr/v2/cobv/d2c13a7-e2bf8a", "tipoCob" => "cobv" }, "status" => "ATIVA",
           "devedor" => { "cpf" => "52998224725", "nome" => "Maria Souza" }, "recebedor" => { "nome" => "ESCOLA ALFA", "nomeFantasia" => "ALFA" },
           "valor" => { "original" => "1250.00" }, "chave" => "pix@alfa.com.br" }.freeze
  EMV = "00020101021226930014br.gov.bcb.pix2571qrpix-h.bradesco.com.br/qr/v2/cobv/d2c13a7-e2bf8a5204000053039865802BR5911ESCOLA ALFA6008CURITIBA62070503***63041D3A".freeze
  PNG = Payments::Providers::Fake::PNG

  setup do
    @alfa = tenants(:alfa)
    @bradesco = Payments::Providers::Bradesco.new
    @payer = { name: "Maria Souza", document: "52998224725",
               address: { "street" => "Rua das Flores", "number" => "10", "district" => "Centro", "city" => "Curitiba", "state" => "PR", "zip" => "80010000" } }
  end

  def account = (@account ||= make_bradesco_account(@alfa))

  def emv_response(status: "ATIVA", base64: Base64.strict_encode64(PNG)) = { "cobv" => COBV.merge("status" => status), "emv" => EMV, "base64" => base64 }

  def issue(**options) = @bradesco.issue_pix(account, custom_id: TXID, amount_cents: 125_000, due_on: Date.new(2026, 11, 30), payer: @payer, options: options)

  test "o Bradesco oferece só Pix enquanto a autenticação do boleto não existe (R284j)" do
    assert_equal %w[pix], @bradesco.manifest.modalities
    assert_equal %w[pix], @bradesco.modalities
    assert_includes Payments::Providers.for_modality("pix"), "bradesco"
    assert_not_includes Payments::Providers.for_modality("boleto"), "bradesco"
    with_bradesco_boleto_auth { assert_equal %w[boleto pix], @bradesco.manifest.modalities }
  end

  test "token por formulário, com Basic e o certificado, e o token na chamada (P l. 310-364)" do
    client = use_bradesco_client(bradesco_client.on(:put, "/v2/cobv-emv/", status: 201, body: emv_response))
    issue
    token = client.to("/oauth/token").first
    assert_equal "https://qrpix-h.bradesco.com.br/oauth/token", token.url
    assert_equal "grant_type=client_credentials", token.body
    assert_equal "application/x-www-form-urlencoded", token.headers["Content-Type"]
    assert_equal "Basic #{Base64.strict_encode64("#{account.secrets['client_id']}:#{account.secrets['client_secret']}")}", token.headers["Authorization"]
    assert_kind_of OpenSSL::X509::Certificate, token.tls[:cert], "mTLS também no token"
    call = client.to("/v2/cobv-emv/").first
    assert_equal "Bearer TOKEN-PIX-BRADESCO", call.headers["Authorization"]
    assert_kind_of OpenSSL::PKey::PKey, call.tls[:key]
  end

  test "emissão por cobv-emv: corpo do padrão, desconto até a véspera, nome no QR Code, copia e cola e imagem da resposta embrulhada (P l. 4757-5539)" do
    client = use_bradesco_client(bradesco_client.on(:put, "/v2/cobv-emv/#{TXID}", status: 201, body: emv_response))
    issued = issue(fine_percent: 2, interest_percent: 1, discount_percent: 5)
    body = JSON.parse(client.to("/v2/cobv-emv/").first.body)
    assert_equal({ "dataDeVencimento" => "2026-11-30", "validadeAposVencimento" => 30 }, body["calendario"])
    assert_equal "1250.00", body.dig("valor", "original")
    assert_equal({ "modalidade" => 2, "valorPerc" => "2.00" }, body.dig("valor", "multa"))
    assert_equal({ "modalidade" => 3, "valorPerc" => "1.00" }, body.dig("valor", "juros"))
    assert_equal [ { "data" => "2026-11-29", "valorPerc" => "5.00" } ], body.dig("valor", "desconto", "descontoDataFixa"), "data menor que o vencimento (P l. 4210)"
    assert_equal "ESCOLA ALFA", body["nomePersonalizacaoQr"]
    assert_equal({ "nome" => "Maria Souza", "cpf" => "52998224725", "logradouro" => "Rua das Flores, 10", "cidade" => "Curitiba", "uf" => "PR", "cep" => "80010000" }, body["devedor"])
    assert_equal [ TXID, "active", 125_000, Date.new(2026, 11, 30), EMV ], [ issued.external_id, issued.status, issued.amount_cents, issued.due_on, issued.copy_paste ]
    assert_equal PNG, issued.qr_png
  end

  test "imagem que não é PNG (ou com prefixo data:) é aceita só se for PNG; senão o QR Code é gerado aqui (R273)" do
    use_bradesco_client(bradesco_client.on(:put, "/v2/cobv-emv/", status: 201, body: emv_response(base64: "data:image/png;base64,#{Base64.strict_encode64(PNG)}")))
    assert_equal PNG, issue.qr_png
    use_bradesco_client(bradesco_client.on(:put, "/v2/cobv-emv/", status: 201, body: emv_response(base64: Base64.strict_encode64("<svg/>"))))
    assert_nil issue.qr_png
  end

  test "412 com o txid em uso vira consulta da cobrança (P l. 1080)" do
    client = use_bradesco_client(bradesco_client.on(:put, "/v2/cobv-emv/", status: 412, body: { "title" => "Erro", "status" => 412, "detail" => "4001 Identificador da transação já está em uso" })
                                                 .on(:get, "/v2/cobv/#{TXID}", body: COBV.merge("pixCopiaECola" => EMV)))
    issued = issue
    assert_equal [ "active", EMV ], [ issued.status, issued.copy_paste ]
    assert_equal 1, client.to("/v2/cobv/#{TXID}").size
  end

  test "consulta: pago com horário acentuado, 204 é não encontrada, devolução somada (P l. 6307-6749)" do
    paid = COBV.merge("status" => "CONCLUIDA", "pix" => [ { "endToEndId" => E2E, "txid" => TXID, "valor" => "1250.00", "horário" => "2026-11-14T10:01:00Z",
                                                             "devolucoes" => [ { "id" => "D1", "valor" => "300.00", "status" => "DEVOLVIDO" } ] } ])
    use_bradesco_client(bradesco_client.on(:get, "/v2/cobv/#{TXID}", body: paid))
    issued = @bradesco.fetch_pix(account, TXID)
    assert_equal [ "paid", 125_000, 30_000 ], [ issued.status, issued.paid_cents, issued.refunded_cents ]
    use_bradesco_client(bradesco_client.on(:get, "/v2/cobv/#{TXID}", status: 204, raw: ""))
    assert_raises(Payments::Providers::Error) { @bradesco.fetch_pix(account, TXID) }
  end

  test "cancelamento manda só o estado (P l. 2392-2394, 5641-5644)" do
    client = use_bradesco_client(bradesco_client.on(:patch, "/v2/cobv/#{TXID}", body: COBV.merge("status" => "REMOVIDA_PELO_USUARIO_RECEBEDOR")))
    assert_equal "canceled", @bradesco.cancel_pix(account, TXID).status
    assert_equal({ "status" => "REMOVIDA_PELO_USUARIO_RECEBEDOR" }, JSON.parse(client.to("/v2/cobv/").first.body))
  end

  test "devolução pelo endToEndId do pagamento, sem acento no caminho, aceita 200 (P l. 8009-8162)" do
    paid = COBV.merge("status" => "CONCLUIDA", "pix" => [ { "endToEndId" => E2E, "txid" => TXID, "valor" => "1250.00" } ])
    client = use_bradesco_client(bradesco_client.on(:get, "/v2/cobv/#{TXID}", body: paid)
                                                 .on(:put, "/v2/pix/#{E2E}/devolucao/", body: { "id" => "D1", "valor" => "300.00", "status" => "EM_PROCESSAMENTO" }))
    @bradesco.refund_pix(account, TXID, amount_cents: 30_000)
    request = client.to("/devolucao/").first
    assert_equal({ "valor" => "300.00" }, JSON.parse(request.body))
    assert_match %r{/devolucao/[A-F0-9]{32}\z}, request.url, "o id da devolução volta em maiúsculas no manual (P l. 8058)"
  end

  test "erros: 401 renova o token uma vez, 403 é recusa, 503 é indisponível e o Pix repete (R272)" do
    count = 0
    client = use_bradesco_client(bradesco_client.on(:get, "/v2/cobv/") { count += 1; count == 1 ? { status: 401, body: {} } : { status: 200, body: COBV } })
    assert_equal "active", @bradesco.fetch_pix(account, TXID).status
    assert_equal 2, client.to("/oauth/token").size
    use_bradesco_client(bradesco_client.on(:get, "/v2/cobv/", status: 403, body: { "title" => "Acesso Negado", "detail" => "escopo" }))
    error = assert_raises(Payments::Providers::Error) { @bradesco.fetch_pix(account, TXID) }
    assert_not_kind_of Payments::Providers::NetworkError, error
    assert_includes error.message, "Acesso Negado"
    use_bradesco_client(bradesco_client.on(:get, "/v2/cobv/", status: 500, body: {}))
    assert_predicate assert_raises(Payments::Providers::NetworkError) { @bradesco.fetch_pix(account, TXID) }, :retry_safe
  end

  test "webhook: lê só o que importa do pix[], autentica pelo hmac da URL e ignora os campos do pagador (P l. 8851-9001; BR5)" do
    secret = account.rotate_webhook_secret!
    body = { "pix" => [ { "endToEndId" => E2E, "txid" => TXID, "valor" => "1250.00", "componentesValor" => { "original" => { "valor" => "1250.00" } },
                          "horario" => "2026-11-14T10:01:00Z", "pagador" => { "cpf" => "529XXXXX725", "nomepagador" => "MARIA SOUZA" } } ] }.to_json
    notifications = @bradesco.parse_notification(account, body: body, headers: {}, context: { query: { "hmac" => Payments::WebhookUrl.token(account, secret) } })
    notification = notifications.sole
    assert_equal [ E2E, :paid, TXID, 125_000 ], [ notification.event_id, notification.kind, notification.external_id, notification.amount_cents ]
    assert_not notification.to_h.values.any? { |value| value.to_s.include?("MARIA") }
    assert_raises(Payments::Providers::InvalidSignature) { @bradesco.parse_notification(account, body: body, headers: {}, context: { query: { "hmac" => "0" * 32 } }) }
    assert_equal [], @bradesco.parse_notification(account, body: "{}", headers: {}, context: {})
  end

  test "lista de recebidos (GET /v2/pix) por páginas, com o mesmo identificador do webhook (R284b, R284c)" do
    page = ->(number, pix) { { "parametros" => { "inicio" => "x", "fim" => "y", "paginacao" => { "paginaAtual" => number, "itensPorPagina" => 100, "quantidadeDePaginas" => 2 } }, "pix" => pix } }
    client = use_bradesco_client(bradesco_client.on(:get, "/v2/pix?") do |request|
      request.url.include?("paginaAtual%5D=1") || request.url.include?("paginaAtual=1") ? { status: 200, body: page.call(1, [ { "endToEndId" => "E2", "txid" => "T2", "valor" => "10.00" } ]) } : { status: 200, body: page.call(0, [ { "endToEndId" => E2E, "txid" => TXID, "valor" => "1250.00", "horario" => "2026-11-14T10:01:00Z" } ]) }
    end)
    from = Time.zone.parse("2026-11-14 09:00")
    notifications = @bradesco.list_paid(account, from: from, to: from + 1.hour)
    assert_equal [ E2E, "E2" ], notifications.map(&:event_id)
    first = client.to("/v2/pix?").first.url
    assert_includes first, "inicio=2026-11-14T12%3A00%3A00Z"
    assert_includes first, "txIdPresente=true"
    assert_equal 2, client.to("/v2/pix?").size
  end

  test "cadastro do webhook por chave, com a URL de hmac de 32 (P l. 8790-8847; R284g)" do
    account.rotate_webhook_secret!
    client = use_bradesco_client(bradesco_client.on(:put, "/v2/webhook/", body: { "webhookUrl" => "x", "chave" => "pix@alfa.com.br" }))
    with_config(public_url: "https://crm.areacli.com") do
      url = Payments::WebhookRegistration.new(account).call
      request = client.to("/v2/webhook/pix%40alfa.com.br").first
      assert_equal({ "webhookUrl" => url }, JSON.parse(request.body))
      assert_equal url, account.reload.webhook_registered_url
    end
  end

  test "emitido pelo Issuer: o Pix ativo com o QR Code do banco guardado (R271, R273)" do
    account
    use_bradesco_client(bradesco_client.on(:put, "/v2/cobv-emv/", status: 201, body: emv_response))
    bill = make_bill(@alfa, number: "NF-1", amount_cents: 125_000)
    instrument = Payments::Issuer.new.request(tenant: @alfa, kind: "pix", amount_cents: 125_000, customer: bill.customer, due_on: Date.current + 10, environment: "sandbox", object: bill)
    perform_enqueued_jobs
    instrument.reload
    assert instrument.state_active?, instrument.failure_reason
    assert_equal EMV, instrument.copy_paste
    assert_equal Digest::SHA256.hexdigest(PNG), instrument.pix_qr_sha256
  end
end
