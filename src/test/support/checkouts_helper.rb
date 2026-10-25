# Links de checkout nos testes (12, parte C): contas do fornecedor falso, instrumentos emitidos e o link pronto.
module CheckoutsHelper
  # Instrumento (boleto ou Pix) emitido pelo fornecedor falso, ativo, com arquivo guardado.
  def issued_instrument(tenant, customer, kind, amount_cents: 99_900, due_on: Date.current + 10, environment: "production")
    unless tenant.payment_accounts.exists?(modality: kind, environment: environment)
      make_account(tenant, modality: kind, environment: environment, config: { "connection_result" => "ok", "pix_key" => "p@a.com" }, nickname: "#{kind} #{tenant.id} #{environment}")
    end
    instrument = Payments::Issuer.new.request(tenant: tenant, kind: kind, amount_cents: amount_cents, customer: customer, due_on: due_on, environment: environment)
    IssueInstrumentJob.perform_now(instrument.id)
    instrument.reload
  end

  def make_card_account(tenant, environment: "production", max_installments: 6)
    tenant.payment_accounts.find_by(modality: "card", environment: environment) ||
      make_account(tenant, modality: "card", environment: environment, config: { "connection_result" => "ok", "max_installments" => max_installments }, nickname: "cartão #{tenant.id} #{environment}")
  end

  # Link com cartão (padrão) e, se pedido, boleto e Pix emitidos. Devolve o link.
  def make_checkout(tenant: tenants(:alfa), customer: nil, card: true, boleto: false, pix: false, amount_cents: 99_900, **options)
    customer ||= Customer.find_by(tenant_id: tenant.id, document: Document.normalize(PaymentsHelper::MARIA)) || make_customer(tenant)
    make_card_account(tenant) if card
    instruments = []
    instruments << issued_instrument(tenant, customer, "boleto", amount_cents: amount_cents) if boleto
    instruments << issued_instrument(tenant, customer, "pix", amount_cents: amount_cents) if pix
    Payments::Checkouts.create(tenant: tenant, customer: customer, instruments: instruments, card: (card ? true : false), amount_cents: amount_cents, **options)
  end

  # Corpo e cabeçalho CSP em partes: { "script-src" => ["'self'", ...] }.
  def csp_of(response)
    response.headers["Content-Security-Policy"].to_s.split(";").map(&:strip).reject(&:empty?).to_h { |item| name, *sources = item.split(" "); [ name, sources ] }
  end
end
