require "test_helper"

# Adaptador Efí, cartão e devolução (12, parte C) com respostas gravadas à mão: nenhum teste chama a Efí real (R258, R278).
class PaymentsEfiCardTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @efi = Payments::Providers::Efi.new
    @payer = { name: "Maria Souza", document: "52998224725", email: "maria@exemplo.com.br", phone: "11988880001",
               address: { "street" => "Rua das Flores", "number" => "10", "district" => "Centro", "city" => "Curitiba", "state" => "PR", "zip" => "80010000" } }
  end

  APPROVED = { "code" => 200, "data" => { "charge_id" => 5_078_131, "total" => 100_000, "status" => "approved", "installments" => 2, "installment_value" => 50_000, "payment" => "credit_card" } }.freeze
  def declined(reason, retry_flag) = { "code" => 200, "data" => { "charge_id" => 5_078_132, "status" => "unpaid", "refusal" => { "reason" => reason, "retry" => retry_flag } } }

  def card_account
    @card ||= make_efi_account(@alfa, modality: "card")
  end

  def charge(client_body = APPROVED, **overrides)
    client = use_efi_client(efi_client.on(:post, "/v1/charge/one-step", body: client_body))
    result = @efi.charge_card(card_account, **{ custom_id: "K" * 32, amount_cents: 100_000, installments: 2, payment_token: "TOKEN-DO-NAVEGADOR-1", payer: @payer }.merge(overrides))
    [ result, client ]
  end

  test "o corpo do one-step leva só o payment_token e as parcelas, com o cliente e o endereço; nenhum dado de cartão (R278)" do
    _result, client = charge
    request = client.to("/v1/charge/one-step").first
    body = JSON.parse(request.body)
    card = body.dig("payment", "credit_card")
    assert_equal({ "installments" => 2, "payment_token" => "TOKEN-DO-NAVEGADOR-1",
                   "customer" => { "name" => "Maria Souza", "cpf" => "52998224725", "email" => "maria@exemplo.com.br", "phone_number" => "11988880001" },
                   "billing_address" => { "street" => "Rua das Flores", "number" => "10", "neighborhood" => "Centro", "zipcode" => "80010000", "city" => "Curitiba", "state" => "PR" } }, card)
    assert_equal({ "custom_id" => "K" * 32 }, body["metadata"])
    assert_equal [ { "name" => "Cobrança", "value" => 100_000, "amount" => 1 } ], body["items"]
    assert_equal "Bearer TOKEN-COBRANCAS", request.headers["Authorization"]
    assert_equal "https://cobrancas-h.api.efipay.com.br/v1/charge/one-step", request.url
    assert_not_includes request.body, "cvv"
    assert_no_match(/\d{13,19}/, request.body, "nenhum número de cartão (o telefone e o documento têm menos de 13 dígitos)")
  end

  test "pagador de CNPJ usa juridical_person; sem e-mail, telefone ou endereço completo, esses campos não vão" do
    _result, client = charge(payer: { name: "Escola Ltda", document: "11222333000181", address: { "street" => "Rua" } })
    card = JSON.parse(client.to("/v1/charge/one-step").first.body).dig("payment", "credit_card")
    assert_equal({ "juridical_person" => { "corporate_name" => "Escola Ltda", "cnpj" => "11222333000181" } }, card["customer"])
    assert_not card.key?("billing_address")
  end

  test "aprovado pelo emissor: aprovado, com o identificador, as parcelas e o total; ainda não pago" do
    result, = charge
    assert_equal [ "5078131", "approved", 100_000, 2 ], [ result.external_id, result.status, result.amount_cents, result.installments ]
    assert_not result.declined?
  end

  test "recusa (unpaid): o motivo é classificado e o retry vem do fornecedor" do
    {
      "Invalid card data." => [ "invalid_data", true ],
      "Transaction not authorized for security reasons." => [ "security", false ],
      "Transaction not authorized, try again later." => [ "try_later", true ],
      "Operação negada pelo emissor" => [ "other", false ]
    }.each do |reason, (code, retry_flag)|
      result, = charge(declined(reason, retry_flag))
      assert result.declined?, reason
      assert_equal [ code, retry_flag, reason ], [ result.refusal_code, result.retry, result.refusal_reason ]
    end
  end

  test "erro 4xx da Efí vira erro curto e seguro; 503 vira rede segura de repetir; 500 não" do
    use_efi_client(efi_client.on(:post, "/v1/charge/one-step", status: 400, body: { "error_description" => { "message" => "payment_token inválido" } }))
    error = assert_raises(Payments::Providers::Error) { @efi.charge_card(card_account, custom_id: "K" * 32, amount_cents: 1, installments: 1, payment_token: "TOKEN-DO-NAVEGADOR-1", payer: @payer) }
    assert_includes error.message, "payment_token inválido"
    assert_not_includes error.message, "TOKEN-DO-NAVEGADOR-1"
    use_efi_client(efi_client.on(:post, "/v1/charge/one-step", status: 503, body: {}))
    assert_equal true, assert_raises(Payments::Providers::NetworkError) { @efi.charge_card(card_account, custom_id: "K" * 32, amount_cents: 1, installments: 1, payment_token: "TOKEN-DO-NAVEGADOR-1", payer: @payer) }.retry_safe
    use_efi_client(efi_client.on(:post, "/v1/charge/one-step", status: 500, body: {}))
    assert_equal false, assert_raises(Payments::Providers::NetworkError) { @efi.charge_card(card_account, custom_id: "K" * 32, amount_cents: 1, installments: 1, payment_token: "TOKEN-DO-NAVEGADOR-1", payer: @payer) }.retry_safe
  end

  test "parcelas: GET /v1/installments por bandeira e valor; com juros o total é parcela vezes número; sem juros, o valor emitido" do
    body = { "code" => 200, "data" => { "rate" => 0, "name" => "visa", "installments" => [
      { "installment" => 1, "has_interest" => false, "value" => 100_000, "currency" => "1.000,00", "interest_percentage" => 0 },
      { "installment" => 3, "has_interest" => false, "value" => 33_334, "currency" => "333,34", "interest_percentage" => 0 },
      { "installment" => 6, "has_interest" => true, "value" => 17_500, "currency" => "175,00", "interest_percentage" => 500 }
    ] } }
    client = use_efi_client(efi_client.on(:get, "/v1/installments", body: body))
    options = @efi.installments(card_account, amount_cents: 100_000, brand: "visa")
    assert_equal "https://cobrancas-h.api.efipay.com.br/v1/installments?brand=visa&total=100000", client.to("/v1/installments").first.url
    assert_equal [ [ 1, 100_000, 100_000, false ], [ 3, 33_334, 100_000, false ], [ 6, 17_500, 105_000, true ] ], options.map { |o| [ o.installments, o.installment_cents, o.total_cents, o.has_interest ] }
  end

  test "sem bandeira conhecida só oferece à vista e nem chama a Efí" do
    use_efi_client(efi_client)
    options = @efi.installments(card_account, amount_cents: 5_000, brand: nil)
    assert_equal [ [ 1, 5_000 ] ], options.map { |o| [ o.installments, o.total_cents ] }
    assert_equal [ [ 1, 5_000 ] ], @efi.installments(card_account, amount_cents: 5_000, brand: "outra-coisa").map { |o| [ o.installments, o.total_cents ] }
  end

  test "reembolso de cartão: POST /v1/charge/card/:id/refund com o valor em centavos" do
    client = use_efi_client(efi_client.on(:post, "/v1/charge/card/5078131/refund", body: { "code" => 200, "message" => "reembolso em processamento" }))
    refund = @efi.refund_card(card_account, "5078131", amount_cents: 20_000)
    assert_equal({ "amount" => 20_000 }, JSON.parse(client.to("/refund").first.body))
    assert_equal [ "5078131", 20_000 ], [ refund.external_id, refund.amount_cents ]
  end

  test "devolução de Pix: acha o endToEndId na cobrança paga e faz PUT idempotente com o valor em texto" do
    pix = make_efi_account(@alfa, modality: "pix")
    client = use_efi_client(efi_client.on(:get, "/v2/cobv/#{'T' * 32}", body: { "status" => "CONCLUIDA", "txid" => "T" * 32, "valor" => { "original" => "100.00" }, "pix" => [ { "endToEndId" => "E12345678202610251000abcdef", "valor" => "100.00" } ] })
                                .on(:put, "/v2/pix/E12345678202610251000abcdef/devolucao/", body: { "id" => "dev", "valor" => "30.00", "status" => "EM_PROCESSAMENTO" }))
    refund = @efi.refund_pix(pix, "T" * 32, amount_cents: 3_000)
    put = client.to("/devolucao/").first
    assert_equal "put", put.method
    assert_equal({ "valor" => "30.00" }, JSON.parse(put.body))
    assert_match(%r{/devolucao/[0-9a-f]{32}\z}, put.url)
    again = @efi.refund_pix(pix, "T" * 32, amount_cents: 3_000)
    assert_equal put.url, client.to("/devolucao/").last.url, "o mesmo pedido repete o mesmo identificador de devolução"
    assert_equal [ 3_000, 3_000 ], [ refund.amount_cents, again.amount_cents ]
  end

  test "devolução de Pix ainda não pago é recusada com mensagem" do
    pix = make_efi_account(@alfa, modality: "pix")
    use_efi_client(efi_client.on(:get, "/v2/cobv/", body: { "status" => "ATIVA", "txid" => "T" * 32, "valor" => { "original" => "100.00" } }))
    error = assert_raises(Payments::Providers::Error) { @efi.refund_pix(pix, "T" * 32, amount_cents: 3_000) }
    assert_includes error.message, "ainda não foi pago"
  end

  test "o manifesto declara o módulo, a biblioteca fixada (versão e SHA-256) e a conta dá os valores públicos e os domínios" do
    declared = Payments::Providers::Efi::MANIFEST.capabilities.fetch(:card_checkout)
    assert_equal [ "payments/drivers/efi", "payment-token-efi", "3.4.1" ], declared.values_at(:driver, :script, :script_version)
    assert_equal({ "payee_code" => "ac0123456789abcdef", "environment" => "sandbox" }, @efi.card_checkout_config(card_account))
    hosts = @efi.card_checkout_hosts(card_account)
    assert_includes hosts[:connect], "https://tokenizer.sejaefi.com.br"
    assert_includes hosts[:connect], "https://cobrancas-h.api.efipay.com.br"
    assert_empty hosts[:frame]
    production = make_efi_account(@alfa, modality: "card", environment: "production", nickname: "Efí produção")
    assert_not_includes @efi.card_checkout_hosts(production)[:connect], "https://cobrancas-h.api.efipay.com.br"
    assert_equal "production", @efi.card_checkout_config(production)["environment"]
  end
end
