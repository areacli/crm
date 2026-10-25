require "test_helper"

# Aviso de fornecedor (12, parte D, R282): idempotência por conta e identificador, reabertura do token reaproveitado, endereço do webhook da conta.
class PaymentEventTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @account = make_account(@alfa, modality: "pix", config: { "connection_result" => "ok", "pix_key" => "p@a.com" })
    @secret = @account.rotate_webhook_secret!
  end

  def notification(id = "E1", **options) = Payments::Providers::Notification.new(event_id: id, kind: :paid, external_id: "X", amount_cents: 100, **options)

  test "o mesmo identificador na mesma conta não duplica; em outra conta é outro aviso (R282)" do
    first, new = PaymentEvent.record(@account, notification)
    assert new
    again, requeue = PaymentEvent.record(@account, notification)
    assert_equal [ first, false ], [ again, requeue ]
    other = make_account(@alfa, modality: "boleto", environment: "production")
    assert_not_equal first, PaymentEvent.record(other, notification).first
    assert_equal 2, PaymentEvent.count
  end

  test "aviso que reaproveita o identificador (token da Efí) reabre o anterior já terminado, mas não o que ainda está por fazer" do
    event, = PaymentEvent.record(@account, notification("TOKEN", reprocess: true))
    assert_equal [ event, false ], PaymentEvent.record(@account, notification("TOKEN", reprocess: true)), "ainda recebido"
    event.finish!(:applied, "ok")
    reopened, requeue = PaymentEvent.record(@account, notification("TOKEN", reprocess: true))
    assert requeue
    assert_equal [ "received", nil, 0 ], [ reopened.state, reopened.outcome, reopened.attempts ]
  end

  test "o aviso sem reprocessamento terminado continua terminado" do
    event, = PaymentEvent.record(@account, notification)
    event.finish!(:applied, "ok")
    assert_equal [ event, false ], PaymentEvent.record(@account, notification)
    assert_equal "applied", event.reload.state
  end

  test "o aviso de volta no formato do adaptador mantém o token, o endToEndId e o custom_id" do
    event, = PaymentEvent.record(@account, notification("E9", token: "TOK", end_to_end_id: "E2E", custom_id: "C1"))
    back = event.to_notification
    assert_equal [ "E9", :paid, "X", 100, "TOK", "E2E", "C1" ], [ back.event_id, back.kind, back.external_id, back.amount_cents, back.token, back.end_to_end_id, back.custom_id ]
  end

  test "estado e tipo fora da lista são recusados pelo modelo e pelo banco" do
    assert_raises(ActiveRecord::RecordInvalid) { PaymentEvent.create!(tenant: @alfa, account: @account, event_id: "Z", kind: "paid", state: "inventado") }
    assert_raises(ActiveRecord::StatementInvalid) { PaymentEvent.new(tenant: @alfa, account: @account, event_id: "Z", kind: "paid").tap { |event| event.state = "paid" }.save!(validate: false) }
  end

  test "o credor do aviso é o da conta" do
    event = PaymentEvent.new(tenant: tenants(:beta), account: @account, event_id: "Z", kind: "paid")
    assert_not event.valid?
    assert_includes event.errors[:account], "é de outro credor"
  end

  test "o endereço do webhook leva o HMAC derivado do segredo, nunca o segredo; sem endereço público ou segredo não há URL" do
    old = Rails.configuration.x.payments.public_url
    Rails.configuration.x.payments.public_url = "https://crm.exemplo.com.br/"
    url = Payments::WebhookUrl.for(@account)
    assert_equal "https://crm.exemplo.com.br/webhooks/pagamentos/contas/#{@account.id}?hmac=#{Payments::WebhookUrl.token(@account, @secret)}", url
    assert_not_includes url, @secret
    assert Payments::WebhookUrl.valid?(@account, Payments::WebhookUrl.token(@account, @secret))
    assert_not Payments::WebhookUrl.valid?(@account, nil)
    assert_not Payments::WebhookUrl.valid?(@account, Payments::WebhookUrl.token(@account, "outro"))
    Rails.configuration.x.payments.public_url = nil
    assert_nil Payments::WebhookUrl.for(@account)
  ensure
    Rails.configuration.x.payments.public_url = old
  end
end
