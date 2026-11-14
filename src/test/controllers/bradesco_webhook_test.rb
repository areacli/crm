require "test_helper"

# Os dois caminhos pela rota de verdade (12, revisão 4, R284b e R284c), com o Pix do Bradesco: o aviso com `hmac` errado responde 401 e não grava
# nada, e o mesmo pagamento entra pela lista de recebidos; o aviso certo depois disso não gera outro pagamento. Nenhum teste chama o Bradesco.
class BradescoWebhookTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  TXID = "BRADESCOTXID0000000000000000001".freeze
  E2E = "E60746948202611141000A1B2C3D4E5F6G".freeze

  setup do
    @alfa = tenants(:alfa)
    @account = make_bradesco_account(@alfa)
    @secret = @account.rotate_webhook_secret!
    bill = make_bill(@alfa, number: "NF-1", amount_cents: 125_000)
    cobv = { "calendario" => { "dataDeVencimento" => (Date.current + 10).iso8601 }, "txid" => TXID, "status" => "ATIVA", "valor" => { "original" => "1250.00" } }
    @paid_cobv = cobv.merge("status" => "CONCLUIDA", "pix" => [ { "endToEndId" => E2E, "txid" => TXID, "valor" => "1250.00", "horario" => Time.current.utc.iso8601 } ])
    @client = use_bradesco_client(bradesco_client.on(:put, "/v2/cobv-emv/", status: 201, body: { "cobv" => cobv, "emv" => "000201COPIAECOLA", "base64" => "" })
                                                  .on(:get, "/v2/cobv/", body: @paid_cobv)
                                                  .on(:get, "/v2/pix?", body: { "parametros" => { "paginacao" => { "quantidadeDePaginas" => 1 } }, "pix" => @paid_cobv["pix"] }))
    @instrument = Payments::Issuer.new.request(tenant: @alfa, kind: "pix", amount_cents: 125_000, customer: bill.customer, due_on: Date.current + 10, environment: "sandbox",
                                               object: bill, custom_id: TXID)
    perform_enqueued_jobs
    @bill = bill
  end

  def deliver(hmac)
    body = { "pix" => [ { "endToEndId" => E2E, "txid" => TXID, "valor" => "1250.00", "horario" => Time.current.utc.iso8601 } ] }.to_json
    post "/webhooks/pagamentos/contas/#{@account.id}?hmac=#{hmac}", params: body, headers: { "CONTENT_TYPE" => "application/json" }
  end

  test "hmac errado: 401 sem gravar nada, e o pagamento entra pela lista; o aviso certo depois não paga de novo (R284b, R284c)" do
    assert @instrument.reload.state_active?, @instrument.failure_reason
    assert_no_difference -> { PaymentEvent.count } do
      deliver("0" * 32)
      assert_response :unauthorized
    end
    perform_enqueued_jobs(only: ProcessPaymentEventJob) { Payments::PaidList.new(@account.reload).call }
    assert @instrument.reload.state_paid?
    assert_predicate @bill.reload, :paid?
    perform_enqueued_jobs { deliver(Payments::WebhookUrl.token(@account, @secret)) }
    assert_response :accepted
    assert_equal [ 1, 1 ], [ PaymentEvent.count, Payment.count ]
    assert_equal E2E, PaymentEvent.sole.event_id
  end

  test "a rota aceita o aviso com /pix no fim e o hmac de 64 de antes da revisão 4 (R284g)" do
    body = { "pix" => [] }.to_json
    post "/webhooks/pagamentos/contas/#{@account.id}/pix?hmac=#{Payments::WebhookUrl.full_token(@account, @secret)}", params: body, headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :accepted
  end
end
