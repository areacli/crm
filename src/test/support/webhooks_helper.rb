# Webhooks e conciliação nos testes (12, parte D): instrumentos emitidos pelo fornecedor falso ligados a um título, avisos assinados e o que o
# fornecedor passa a dizer na consulta. Nenhum teste chama fornecedor real.
module WebhooksHelper
  # Credor com o título NF-1 (R$ 1.000,00) e um instrumento ativo ligado a ele. `reference`: "bill" (padrão), "promise", "agreement" ou nil.
  def paid_scenario(tenant = tenants(:alfa), kind: "boleto", amount_cents: 100_000, reference: :bill, due_on: Date.current + 10)
    bill = make_bill(tenant, number: "NF-1", amount_cents: amount_cents)
    ref = reference == :bill ? [ "bill", bill.id ] : reference
    instrument = emit(tenant, bill.customer, kind, amount_cents, reference: ref, due_on: due_on)
    [ bill, instrument ]
  end

  def emit(tenant, customer, kind, amount_cents, reference: nil, due_on: Date.current + 10, environment: "production")
    unless tenant.payment_accounts.exists?(modality: kind, environment: environment)
      make_account(tenant, modality: kind, environment: environment, config: { "connection_result" => "ok", "pix_key" => "p@a.com", "max_installments" => 3 }, nickname: "#{kind} #{tenant.id} #{environment}")
    end
    instrument = Payments::Issuer.new.request(tenant: tenant, kind: kind, amount_cents: amount_cents, customer: customer, due_on: due_on, environment: environment, reference: reference)
    IssueInstrumentJob.perform_now(instrument.id)
    instrument.reload
  end

  def fake_paid!(instrument, paid_cents: nil) = Payments::Providers::Fake.mark_paid!(instrument.external_id, paid_cents: paid_cents)

  # Aviso do falso: corpo, assinatura com o segredo dado e cabeçalhos.
  def signed_notice(secret, *items)
    body = (items.size == 1 ? items.first : { batch: items }).to_json
    [ body, { "CONTENT_TYPE" => "application/json", "X-Signature" => OpenSSL::HMAC.hexdigest("SHA256", secret, body) } ]
  end

  def notice(id:, type: "paid", external_id: nil, amount_cents: nil) = { id: id, type: type, external_id: external_id, amount_cents: amount_cents }

  def stored_event(instrument, id: "EV-#{SecureRandom.hex(3)}", kind: :paid, amount_cents: nil)
    notification = Payments::Providers::Notification.new(event_id: id, kind: kind, external_id: instrument.external_id, amount_cents: amount_cents, occurred_at: Time.current)
    PaymentEvent.record(instrument.account, notification).first
  end
end
