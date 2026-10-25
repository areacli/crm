require "test_helper"

# Webhook por conta de pagamento (12, parte D, R281 a R284) com o fornecedor falso: assinatura, idempotência, resposta rápida sem chamar o fornecedor,
# processamento na fila `webhooks` que consulta antes de mudar, reprocessamento. Nenhum teste chama fornecedor real.
class PaymentAccountWebhooksTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @bill, @instrument = paid_scenario(kind: "pix")
    @account = @instrument.account
    @secret = @account.rotate_webhook_secret!
  end

  def deliver(item, secret: @secret, account: @account, **extra)
    body, headers = signed_notice(secret, item)
    post payment_account_webhook_path(account), params: body, headers: headers.merge(extra)
  end

  def paid_notice(id = "EV-1", **overrides) = notice(id: id, external_id: @instrument.external_id, amount_cents: 100_000, **overrides)

  test "aviso assinado: 202, guardado uma vez, na fila webhooks, sem chamar o fornecedor (R281, R282)" do
    Payments::Providers::Fake.store.freeze # qualquer toque no fornecedor falso quebraria
    assert_enqueued_with(job: ProcessPaymentEventJob, queue: "webhooks") { deliver(paid_notice) }
    assert_response :accepted
    event = PaymentEvent.sole
    assert_equal [ "received", "EV-1", "paid", @instrument.external_id, 100_000, @alfa.id ], [ event.state, event.event_id, event.kind, event.external_id, event.amount_cents, event.tenant_id ]
    assert_nil event.instrument_id, "o instrumento só é ligado depois da consulta"
    assert @instrument.reload.state_active?
  end

  test "o mesmo aviso de novo: um evento só e um job só (R282)" do
    assert_enqueued_jobs(1, only: ProcessPaymentEventJob) { 3.times { deliver(paid_notice) } }
    assert_response :accepted
    assert_equal 1, PaymentEvent.count
  end

  test "vários avisos em um corpo viram um evento cada" do
    body, headers = signed_notice(@secret, paid_notice("EV-1"), paid_notice("EV-2", type: "other"))
    post payment_account_webhook_path(@account), params: body, headers: headers
    assert_equal %w[EV-1 EV-2], PaymentEvent.order(:id).pluck(:event_id)
    assert_equal({ "status" => "received", "events" => 2 }, response.parsed_body)
  end

  test "assinatura errada, ausente ou de outro segredo: 401, nada gravado, nada na fila, recusa registrada (R281)" do
    assert_no_difference -> { PaymentEvent.count } do
      assert_no_enqueued_jobs do
        deliver(paid_notice, secret: "outro-segredo")
        assert_response :unauthorized
        post payment_account_webhook_path(@account), params: paid_notice.to_json, headers: { "CONTENT_TYPE" => "application/json" }
        assert_response :unauthorized
        deliver(paid_notice, "X-Signature" => "0" * 64)
        assert_response :unauthorized
      end
    end
    assert_equal 3, AccessEvent.where(event: "webhook_refused", tenant_id: @alfa.id).count
  end

  test "404 uniforme: conta inexistente, de fornecedor que saiu do código; o corpo é o mesmo" do
    missing = post payment_account_webhook_path(0), params: "{}", headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :not_found
    first_body = response.body
    @account.update_columns(provider: "desconhecido")
    post payment_account_webhook_path(@account), params: "{}", headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :not_found
    assert_equal first_body, response.body
    assert_equal 404, missing
  end

  test "corpo acima de 64 KB: 413 sem ler mais; corpo que não é JSON: 422" do
    post payment_account_webhook_path(@account), params: "x" * 70.kilobytes, headers: { "CONTENT_TYPE" => "application/json", "X-Signature" => "a" }
    assert_response :content_too_large
    body = "isto não é json"
    post payment_account_webhook_path(@account), params: body, headers: { "CONTENT_TYPE" => "application/json", "X-Signature" => OpenSSL::HMAC.hexdigest("SHA256", @secret, body) }
    assert_response :unprocessable_content
    assert_equal 0, PaymentEvent.count
  end

  test "vigência dupla do segredo: o antigo vale por 24 horas depois da troca (R265)" do
    old = @secret
    new_secret = @account.reload.rotate_webhook_secret!
    deliver(paid_notice("EV-A"), secret: old)
    assert_response :accepted
    deliver(paid_notice("EV-B"), secret: new_secret)
    assert_response :accepted
    travel 25.hours do
      deliver(paid_notice("EV-C"), secret: old)
      assert_response :unauthorized
      deliver(paid_notice("EV-D"), secret: new_secret)
      assert_response :accepted
    end
  end

  test "a rota do Pix da Efí com o sufixo /pix chega ao mesmo lugar" do
    body, headers = signed_notice(@secret, paid_notice)
    post "/webhooks/pagamentos/contas/#{@account.id}/pix", params: body, headers: headers
    assert_response :accepted
  end

  test "ponta a ponta: o job consulta, o instrumento paga o título e o aviso fica aplicado (R283, R284)" do
    fake_paid!(@instrument)
    deliver(paid_notice)
    perform_enqueued_jobs(only: ProcessPaymentEventJob)
    event = PaymentEvent.sole
    assert_equal "applied", event.state
    assert_equal @instrument.id, event.instrument_id
    assert @instrument.reload.state_paid?
    assert_predicate @bill.reload, :paid?
    assert_equal 1, Payment.count
  end

  test "o aviso diz pago, a consulta diz ativo: o aviso fica ignorado e nada muda (R283)" do
    deliver(paid_notice)
    perform_enqueued_jobs(only: ProcessPaymentEventJob)
    assert_equal "ignored", PaymentEvent.sole.state
    assert @instrument.reload.state_active?
    assert_equal 0, Payment.count
  end

  test "aviso de instrumento que não é nosso (outro identificador): ignorado" do
    deliver(notice(id: "EV-9", external_id: "NAO-EXISTE", amount_cents: 100))
    perform_enqueued_jobs(only: ProcessPaymentEventJob)
    assert_equal [ "ignored", I18n.t("payments.events.not_ours") ], PaymentEvent.sole.values_at(:state, :outcome)
  end

  test "falha do fornecedor na consulta: tenta de novo; esgotadas as tentativas o aviso fica failed e a reprocessagem o retoma" do
    fake_paid!(@instrument)
    deliver(paid_notice)
    Payments::Providers::Fake.fail_on(:fetch, Payments::Providers::NetworkError.new("fornecedor fora do ar"), times: 99)
    6.times { perform_enqueued_jobs(only: ProcessPaymentEventJob) }
    event = PaymentEvent.sole
    assert_equal [ "failed", "fornecedor fora do ar" ], event.values_at(:state, :outcome)
    assert @instrument.reload.state_active?

    Payments::Providers::Fake.store[:failures].clear
    assert_equal 1, Payments::EventReprocessor.new(@alfa).call
    perform_enqueued_jobs(only: ProcessPaymentEventJob)
    assert_equal "applied", event.reload.state
    assert @instrument.reload.state_paid?
  end

  test "a reprocessagem retoma o aviso parado em received e limita as voltas" do
    event = stored_event(@instrument)
    assert_equal 0, Payments::EventReprocessor.new(@alfa).call, "recente demais"
    event.update_columns(created_at: 1.hour.ago)
    assert_equal 1, Payments::EventReprocessor.new(@alfa).call
    event.update_columns(state: "failed", summary: event.summary.merge("restarts" => PaymentEvent::MAX_RESTARTS))
    assert_equal 0, Payments::EventReprocessor.new(@alfa).call
  end

  test "o evento guarda o mínimo: nada do pagador nem de cartão" do
    deliver(paid_notice)
    event = PaymentEvent.sole
    assert_empty event.attributes.keys & %w[payer_name payer_document payer_address number cvv]
    assert_empty event.summary.keys - %w[token end_to_end_id custom_id restarts]
    assert_no_match(/#{PaymentsHelper::MARIA.delete('^0-9')}|Maria/, event.attributes.to_json)
  end
end
