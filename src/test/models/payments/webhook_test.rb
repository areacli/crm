require "test_helper"

# Webhook de pagamento sem provedor: endpoint assinado por HMAC SHA-256 com segredo por canal, idempotente pelo identificador do evento,
# processado em job na fila `webhooks` (interface agnóstica de provedor: Payments::Gateway + adaptador signed_json).
class Payments::WebhookTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @channel = make_channel(@alfa)
    @secret = @channel.regenerate_webhook_secret!
    @bill = make_bill(@alfa, number: "NF-1", amount_cents: 100_000)
  end

  def payload(id: "evt-1", type: "payment.received", **data)
    { id: id, type: type, data: { identifier: "PIX-W1", document: "52998224725", bill_number: "NF-1", paid_on: (Date.current - 1).iso8601, amount_cents: 100_000,
                                  method: "pix" }.merge(data) }
  end

  def sign(body, secret = @secret) = OpenSSL::HMAC.hexdigest("SHA256", secret, body)

  def deliver(body_hash, secret: @secret, signature: nil, channel: @channel, content_type: "application/json")
    body = body_hash.is_a?(String) ? body_hash : body_hash.to_json
    post payments_webhook_path(channel), params: body, headers: { "CONTENT_TYPE" => content_type, "X-Signature" => signature || sign(body, secret) }
  end

  test "o segredo fica cifrado no banco e o canal sem segredo não recebe" do
    assert_not_equal @secret, PaymentChannel.connection.select_value("select webhook_secret from payment_channels where id = #{@channel.id}")
    assert_equal @secret, @channel.reload.webhook_secret
    semsegredo = make_channel(@alfa, code: "SEM-SEGREDO")
    deliver(payload, channel: semsegredo)
    assert_response :not_found
  end

  test "assinatura errada ou ausente: 401, nada é guardado, nada é enfileirado e a recusa fica registrada" do
    assert_no_difference -> { WebhookEvent.count } do
      assert_no_enqueued_jobs do
        deliver(payload, signature: "0" * 64)
        assert_response :unauthorized
        deliver(payload, secret: "outro-segredo")
        assert_response :unauthorized
        post payments_webhook_path(@channel), params: payload.to_json, headers: { "CONTENT_TYPE" => "application/json" }
        assert_response :unauthorized
      end
    end
    assert_equal 3, AccessEvent.where(event: "webhook_refused").count
  end

  test "chamada válida: guardada, 202 e enfileirada na fila webhooks; o job baixa o título" do
    assert_enqueued_with(job: ProcessWebhookEventJob, queue: "webhooks") { deliver(payload) }
    assert_response :accepted
    event = WebhookEvent.sole
    assert_equal [ "received", "evt-1", @alfa.id ], [ event.status, event.event_id, event.tenant_id ]

    perform_enqueued_jobs
    assert_equal [ "applied", "título quitado" ], event.reload.values_at(:status, :outcome).map(&:to_s)
    assert_predicate @bill.reload, :paid?
    assert_equal [ "applied", 100_000 ], [ Payment.sole.status, Payment.sole.applied_cents ]
    assert_equal "webhook evt-1", Import.payments.last.original_name
  end

  test "idempotência: o reenvio do mesmo evento responde 200, não guarda outra vez e não processa" do
    deliver(payload)
    assert_response :accepted
    assert_no_enqueued_jobs { deliver(payload) }
    assert_response :ok
    assert_equal({ "status" => "duplicate" }, response.parsed_body)
    perform_enqueued_jobs
    assert_equal [ 1, 1 ], [ WebhookEvent.count, Payment.count ]
  end

  test "evento novo com o mesmo identificador de pagamento é ignorado: o pagamento não é registrado duas vezes" do
    deliver(payload)
    perform_enqueued_jobs
    deliver(payload(id: "evt-2"))
    perform_enqueued_jobs
    assert_equal [ 1, 100_000 ], [ Payment.count, @bill.reload.paid_cents ]
    assert_equal [ "applied", "ignored" ], WebhookEvent.order(:id).pluck(:status)
    assert_equal "pagamento já registrado", WebhookEvent.order(:id).last.outcome
  end

  test "executar o job de novo não repete a baixa" do
    deliver(payload)
    perform_enqueued_jobs
    ProcessWebhookEventJob.perform_now(WebhookEvent.sole)
    assert_equal 1, Payment.count
  end

  test "pagamento do webhook segue as políticas do credor: pendente quando o título não está na carteira" do
    deliver(payload(bill_number: "NF-404"))
    perform_enqueued_jobs
    assert_equal "pending", Payment.sole.status
    assert_match(/pendente/, WebhookEvent.sole.outcome)
  end

  test "pagamento do webhook com dados inválidos é recusado com o motivo e não é repetido" do
    deliver(payload(amount_cents: 100_000, method: "cheque"))
    perform_enqueued_jobs
    assert_equal [ "rejected", "meio de pagamento fora da lista" ], WebhookEvent.sole.values_at(:status, :outcome).map(&:to_s)
    assert_equal 0, Payment.count
  end

  test "canal desativado guarda o evento e o recusa; evento de outro tipo é guardado e ignorado" do
    deliver(payload(id: "evt-t", type: "payment.created"))
    perform_enqueued_jobs
    assert_equal "ignored", WebhookEvent.sole.status
    @channel.update!(active: false)
    deliver(payload(id: "evt-i"))
    perform_enqueued_jobs
    assert_equal [ "ignored", "rejected" ], WebhookEvent.order(:id).pluck(:status)
    assert_equal 0, Payment.count
  end

  test "corpo que não é JSON ou sem identificador do evento: 422; corpo grande demais: 413" do
    deliver("isto não é json", content_type: "text/plain")
    assert_response :unprocessable_content
    deliver({ type: "payment.received", data: {} })
    assert_response :unprocessable_content
    deliver("x" * 70.kilobytes, content_type: "text/plain")
    assert_response :content_too_large
    assert_equal 0, WebhookEvent.count
  end

  test "o segredo de um canal não assina o webhook de outro (V10)" do
    beta_channel = make_channel(tenants(:beta))
    other_secret = beta_channel.regenerate_webhook_secret!
    deliver(payload, secret: other_secret)
    assert_response :unauthorized
    deliver(payload, secret: other_secret, channel: beta_channel)
    assert_response :accepted
    assert_equal tenants(:beta).id, WebhookEvent.sole.tenant_id
  end

  test "o job usa a fila webhooks e o gateway só conhece o adaptador signed_json" do
    assert_equal "webhooks", ProcessWebhookEventJob.new.queue_name
    assert_equal %w[signed_json], Payments::Gateway.names
    assert_instance_of Payments::Gateway::SignedJson, Payments::Gateway.for("signed_json")
  end

  test "assinatura aceita o prefixo sha256=" do
    body = payload.to_json
    post payments_webhook_path(@channel), params: body, headers: { "CONTENT_TYPE" => "application/json", "X-Signature" => "sha256=#{sign(body)}" }
    assert_response :accepted
  end
end
