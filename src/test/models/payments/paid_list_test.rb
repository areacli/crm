require "test_helper"

# Os dois caminhos do pagamento (12, revisão 4, R284b a R284d e R284g) com o fornecedor falso: a lista de pagos encontra o webhook num aviso só, reabre
# o "ignorado", não avança quando falha e roda no horário que o manifesto declara. Nenhum teste chama fornecedor real.
class PaymentsPaidListTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  PIX_CONFIG = { "connection_result" => "ok", "pix_key" => "p@a.com" }.freeze

  setup { @alfa = tenants(:alfa) }

  def webhook_notice(instrument, id: "paid:#{instrument.external_id}")
    Payments::Providers::Notification.new(event_id: id, kind: :paid, external_id: instrument.external_id, amount_cents: instrument.amount_cents, occurred_at: Time.current)
  end

  def deliver_by_webhook(instrument, **options)
    event, queue = PaymentEvent.record(instrument.account, webhook_notice(instrument, **options))
    perform_enqueued_jobs { ProcessPaymentEventJob.perform_later(event) } if queue
    event
  end

  def run_list(account, now: Time.current) = perform_enqueued_jobs(only: ProcessPaymentEventJob) { Payments::PaidList.new(account.reload).call(now: now) }

  test "o mesmo pagamento pelo webhook e depois pela lista: um aviso, um pagamento, o título baixado uma vez (R284b)" do
    bill, instrument = paid_scenario(kind: "pix")
    fake_paid!(instrument)
    deliver_by_webhook(instrument)
    assert instrument.reload.state_paid?
    result = run_list(instrument.account)
    assert_equal [ 1, 0 ], [ result.listed, result.queued ], "o pago que o webhook já trouxe não vira outro aviso"
    assert_equal 1, PaymentEvent.count
    assert_equal 1, Payment.count
    assert_predicate bill.reload, :paid?
  end

  test "na ordem inversa, a lista primeiro e o webhook depois: o aviso repetido é ignorado (R284b, R282)" do
    bill, instrument = paid_scenario(kind: "boleto")
    fake_paid!(instrument)
    assert_equal 1, run_list(instrument.account).queued
    assert instrument.reload.state_paid?
    _event, queue = PaymentEvent.record(instrument.account, webhook_notice(instrument))
    assert_not queue
    assert_equal [ 1, 1 ], [ PaymentEvent.count, Payment.count ]
    assert_predicate bill.reload, :paid?
  end

  test "o aviso que terminou ignorado é reaberto pela lista; o aplicado não (R284d)" do
    _bill, instrument = paid_scenario(kind: "pix")
    event = deliver_by_webhook(instrument)
    assert event.reload.state_ignored?, "a consulta ainda dizia ativo"
    fake_paid!(instrument)
    assert_equal 1, run_list(instrument.account).queued
    assert event.reload.state_applied?
    assert instrument.reload.state_paid?
    assert_equal 1, Payment.count

    other = emit(@alfa, instrument.customer, "pix", 50_000)
    fake_paid!(other)
    applied = deliver_by_webhook(other, id: "E2E-OUTRO")
    assert applied.reload.state_applied?
    assert_equal [], PaymentEvent.where(state: "received").to_a
    _event, queue = PaymentEvent.record(other.account, webhook_notice(other, id: "E2E-OUTRO"), reopen_ignored: true)
    assert_not queue, "o aplicado não se reabre"
  end

  test "a lista falhando não avança a última passada, e a seguinte cobre o período (R284c)" do
    _bill, instrument = paid_scenario(kind: "pix")
    account = instrument.account
    account.update_columns(paid_listed_until: 3.hours.ago)
    Payments::Providers::Fake.fail_on(:list_paid, Payments::Providers::NetworkError.new("fora do ar", retry_safe: true), times: 1)
    PaymentPaidListJob.perform_now(account)
    assert_in_delta 3.hours.ago, account.reload.paid_listed_until, 2
    fake_paid!(instrument)
    PaymentPaidListJob.perform_now(account)
    calls = Payments::Providers::Fake.list_calls
    assert_equal 2, calls.size
    assert_in_delta 4.hours.ago, calls.last[:from], 2, "desde a última passada boa, com uma hora de sobra"
    assert_in_delta Time.current, account.reload.paid_listed_until, 2
  end

  test "Pix de outro sistema na mesma chave e instrumento de outra integração não gravam aviso (R284c, V10)" do
    _bill, instrument = paid_scenario(kind: "pix")
    beta = tenants(:beta)
    _other_bill, other = paid_scenario(beta, kind: "pix")
    fake_paid!(other)
    result = run_list(instrument.account)
    assert_equal 0, result.queued
    assert_equal 0, PaymentEvent.where(tenant_id: @alfa.id).count
    assert other.reload.state_active?
  end

  test "horário da passada: a cada N minutos ou uma vez por dia, depois da hora (R284c)" do
    account = make_account(@alfa, modality: "pix", config: PIX_CONFIG)
    now = Time.zone.parse("2026-11-14 10:00")
    assert Payments::PaidList.due?(account, { every: 10 }, now), "nunca listou"
    account.paid_listed_until = now - 5.minutes
    assert_not Payments::PaidList.due?(account, { every: 10 }, now)
    account.paid_listed_until = now - 9.minutes - 30.seconds
    assert Payments::PaidList.due?(account, { every: 10 }, now), "o despachante roda de 10 em 10: um atraso de segundos não pula a passada"
    account.paid_listed_until = Time.zone.parse("2026-11-13 07:20")
    assert_not Payments::PaidList.due?(account, { daily_at: "07:20" }, Time.zone.parse("2026-11-14 07:10"))
    assert Payments::PaidList.due?(account, { daily_at: "07:20" }, Time.zone.parse("2026-11-14 07:20"))
    account.paid_listed_until = Time.zone.parse("2026-11-14 07:20")
    assert_not Payments::PaidList.due?(account, { daily_at: "07:20" }, Time.zone.parse("2026-11-14 16:00")), "uma vez por dia"
  end

  test "o despachante enfileira só as integrações ativas, com lista e no horário (R284c)" do
    due = make_account(@alfa, modality: "pix", nickname: "Pix no horário", config: PIX_CONFIG)
    recent = make_account(@alfa, modality: "boleto", nickname: "Boleto recente")
    recent.update_columns(paid_listed_until: 2.minutes.ago)
    make_account(@alfa, modality: "card", nickname: "Cartão")
    inactive = make_account(tenants(:beta), modality: "pix", nickname: "Pix desativado", active: false, config: PIX_CONFIG)
    PaymentPaidListsDispatchJob.perform_now
    accounts = enqueued_jobs.select { |job| job["job_class"] == "PaymentPaidListJob" }.map { |job| GlobalID::Locator.locate(job["arguments"].first["_aj_globalid"]) }
    assert_includes accounts, due
    assert_not_includes accounts, recent
    assert_not_includes accounts, inactive
    assert accounts.none?(&:card?)
  end

  test "a URL do webhook tem hmac de 32 e cabe em 100 caracteres; o de 64 do mesmo segredo vale (R284g)" do
    account = make_account(@alfa, modality: "boleto")
    secret = account.rotate_webhook_secret!
    with_config(public_url: "https://crm.areacli.com") do
      url = Payments::WebhookUrl.for(account)
      hmac = url[/hmac=(\h+)\z/, 1]
      assert_equal 32, hmac.length
      assert_operator url.length, :<=, Payments::WebhookUrl::MAX_URL
      assert Payments::WebhookUrl.valid?(account, hmac)
      assert Payments::WebhookUrl.valid?(account, Payments::WebhookUrl.full_token(account, secret))
      assert_not Payments::WebhookUrl.valid?(account, hmac[0, 31])
      assert_not Payments::WebhookUrl.valid?(account, Payments::WebhookUrl.full_token(account, "outro")[0, 32])
    end
  end

  test "o cadastro do webhook grava a data e o endereço na integração (R284g)" do
    account = make_account(@alfa, modality: "pix", config: PIX_CONFIG)
    account.rotate_webhook_secret!
    with_config(public_url: "https://crm.areacli.com") do
      url = Payments::WebhookRegistration.new(account).call(now: Time.zone.parse("2026-11-14 09:00"))
      assert_equal [ Time.zone.parse("2026-11-14 09:00"), url ], [ account.reload.webhook_registered_at, account.webhook_registered_url ]
    end
    with_config(public_url: nil) { assert_raises(Payments::Providers::Error) { Payments::WebhookRegistration.new(make_account(@alfa, modality: "boleto")).call } }
  end

  test "a janela fora do ar do manifesto, inclusive a que atravessa a meia-noite (R284h)" do
    adapter = Payments::Providers::Fake.new
    manifest = adapter.manifest.with(capabilities: adapter.manifest.capabilities.merge(quiet_hours: { "boleto" => "00:00-03:00", "pix" => "23:30-01:00" }))
    adapter.define_singleton_method(:manifest) { manifest }
    begin
      assert_equal Time.zone.parse("2026-11-14 03:00"), adapter.quiet_until("boleto", Time.zone.parse("2026-11-14 01:00"))
      assert_nil adapter.quiet_until("boleto", Time.zone.parse("2026-11-14 03:00"))
      assert_nil adapter.quiet_until("boleto", Time.zone.parse("2026-11-13 23:59"))
      assert_equal Time.zone.parse("2026-11-15 01:00"), adapter.quiet_until("pix", Time.zone.parse("2026-11-14 23:45"))
      assert_equal Time.zone.parse("2026-11-15 01:00"), adapter.quiet_until("pix", Time.zone.parse("2026-11-15 00:30"))
      assert_nil adapter.quiet_until("card", Time.zone.parse("2026-11-14 01:00"))
    end
  end
end
