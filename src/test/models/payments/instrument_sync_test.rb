require "test_helper"

# Conciliação do instrumento com o fornecedor (12, parte D, R283 e R284) com o fornecedor falso: consulta antes de mudar, baixa pelo caminho do
# pagamento existente, estorno, vencimento e cancelamento, isolamento por credor (V10). Nenhum teste chama fornecedor real.
class PaymentsInstrumentSyncTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @sync = Payments::InstrumentSync.new
  end

  test "pago na consulta: o instrumento paga o título pelo caminho do pagamento e fica ligado a ele (R284)" do
    bill, instrument = paid_scenario
    fake_paid!(instrument)
    outcome = @sync.call(instrument)
    assert_equal :applied, outcome.kind
    instrument.reload
    assert instrument.state_paid?
    assert_equal [ 100_000, 100_000 ], [ instrument.paid_cents, instrument.payment.amount_cents ]
    assert_predicate bill.reload, :paid?
    payment = Payment.sole
    assert_equal [ "applied", "boleto", "NF-1", instrument.account.channel_id ], [ payment.status, payment.payment_method, payment.bill_number, payment.channel_id ]
    assert_equal "FAKE-BOLETO-1", payment.identifier.delete_prefix("fake:")
    assert_equal "instrumento #{instrument.custom_id}", Import.payments.last.original_name
  end

  test "Pix e cartão entram com o meio certo (R284)" do
    pix_bill, pix = paid_scenario(kind: "pix")
    fake_paid!(pix)
    @sync.call(pix)
    assert_equal "pix", pix.reload.payment.payment_method
    assert_predicate pix_bill.reload, :paid?

    other = make_bill(@alfa, number: "NF-9", amount_cents: 50_000, document: PaymentsHelper::JOAO, contract_code: "CT-9", name: "João")
    checkout = make_checkout(customer: other.customer, amount_cents: 50_000, reference: [ "bill", other.id ])
    assert_equal :approved, Payments::CardCharger.new.charge(checkout, payment_token: "TOKEN-DO-NAVEGADOR-1", installments: 1).kind
    card = checkout.reload.card_instruments.sole
    assert card.state_active?
    assert checkout.state_card_approved?
    fake_paid!(card)
    @sync.call(card)
    assert_equal "credit_card", card.reload.payment.payment_method
    assert checkout.reload.state_paid?
    assert_predicate other.reload, :paid?
  end

  test "o aviso diz pago mas a consulta diz ativo: nada muda (R283)" do
    bill, instrument = paid_scenario
    notification = Payments::Providers::Notification.new(event_id: "E1", kind: :paid, external_id: instrument.external_id, amount_cents: 100_000, occurred_at: Time.current)
    outcome = @sync.call(instrument, notification)
    assert_equal :ignored, outcome.kind
    assert instrument.reload.state_active?
    assert_not_predicate bill.reload, :paid?
    assert_equal 0, Payment.count
  end

  test "repetir a conciliação do instrumento pago não duplica o pagamento (idempotência)" do
    _bill, instrument = paid_scenario
    fake_paid!(instrument)
    @sync.call(instrument)
    assert_equal :ignored, @sync.call(instrument).kind
    assert_equal 1, Payment.count
    assert_equal 1, Import.payments.count
  end

  test "o mesmo identificador de pagamento do canal já registrado só liga o instrumento (planilha antes do aviso)" do
    _bill, instrument = paid_scenario
    fake_paid!(instrument)
    @sync.call(instrument)
    clone = Payment.sole
    other = instrument.dup.tap { |copy| copy.custom_id = SecureRandom.alphanumeric(32); copy.external_id = "OUTRO"; copy.state = "active"; copy.payment = nil; copy.save! }
    Payments::Providers::Fake.store[:instruments]["OUTRO"] = Payments::Providers::Fake.store[:instruments][instrument.external_id].merge(external_id: "OUTRO")
    stored = Payments::Providers::Notification.new(event_id: clone.identifier, kind: :paid, end_to_end_id: clone.identifier)
    @sync.call(other, stored)
    assert_equal clone, other.reload.payment
    assert_equal 1, Payment.count
  end

  test "pago a mais ou a menos: o valor que o fornecedor consultado diz é o que baixa (baixa parcial)" do
    bill, instrument = paid_scenario
    fake_paid!(instrument, paid_cents: 40_000)
    @sync.call(instrument)
    assert_equal 40_000, instrument.reload.paid_cents
    assert_equal 40_000, Payment.sole.applied_cents
    assert_not_predicate bill.reload, :paid?
  end

  test "a pista do valor do aviso só vale se plausível; sem pista nem consulta, vale o valor do instrumento" do
    _bill, instrument = paid_scenario
    Payments::Providers::Fake.store[:instruments][instrument.external_id][:status] = "paid"
    Payments::Providers::Fake.store[:instruments][instrument.external_id][:paid_cents] = nil
    absurd = Payments::Providers::Notification.new(event_id: "E1", kind: :paid, external_id: instrument.external_id, amount_cents: 999_999_999, occurred_at: Time.current)
    @sync.call(instrument, absurd)
    assert_equal 100_000, instrument.reload.paid_cents
  end

  test "promessa (PRM-) e acordo (ACD-) pelo número do objeto cobrado" do
    customer, nf1, _nf2 = promise_scenario(@alfa, charges: false)
    make_channel(@alfa)
    promise = register_promise(customer, [ nf1 ])
    instrument = emit(@alfa, customer, "pix", 100_000, reference: [ "promise", promise.id ])
    fake_paid!(instrument)
    @sync.call(instrument)
    payment = instrument.reload.payment
    assert_equal promise.number, payment.bill_number
    assert_equal promise.id, payment.promise_id
  end

  test "instrumento sem objeto cobrado: fica pago, o pagamento espera o gestor (review) e nada é inventado" do
    customer = make_customer(@alfa)
    instrument = emit(@alfa, customer, "boleto", 100_000)
    fake_paid!(instrument)
    outcome = @sync.call(instrument)
    assert_equal :review, outcome.kind
    assert instrument.reload.state_paid?
    assert_nil instrument.payment
    assert_equal 0, Payment.count
  end

  test "título que não está na carteira vira pagamento pendente, como na planilha (R52a)" do
    bill, instrument = paid_scenario
    instrument.update!(reference_id: 0)
    fake_paid!(instrument)
    assert_equal :review, @sync.call(instrument).kind
    bill.reload
    assert_not_predicate bill, :paid?
  end

  test "vencido e cancelado no fornecedor: o instrumento ativo muda, o pago nunca" do
    _bill, boleto = paid_scenario
    Payments::Providers::Fake.mark_status!(boleto.external_id, "expired")
    assert_equal :applied, @sync.call(boleto).kind
    assert boleto.reload.state_expired?

    pix = emit(@alfa, boleto.customer, "pix", 100_000, reference: [ "bill", Bill.first.id ])
    Payments::Providers::Fake.mark_status!(pix.external_id, "canceled")
    @sync.call(pix)
    assert pix.reload.state_canceled?

    paid_pix = emit(@alfa, boleto.customer, "pix", 100_000, reference: [ "bill", Bill.first.id ])
    fake_paid!(paid_pix)
    @sync.call(paid_pix)
    Payments::Providers::Fake.mark_status!(paid_pix.external_id, "canceled")
    @sync.call(paid_pix)
    assert paid_pix.reload.state_paid?, "pago nunca é cancelado (R276)"
  end

  test "vencido que o cliente paga depois (boleto até a baixa) vira pago" do
    bill, boleto = paid_scenario
    Payments::Providers::Fake.mark_status!(boleto.external_id, "expired")
    @sync.call(boleto)
    fake_paid!(boleto)
    @sync.call(boleto)
    assert boleto.reload.state_paid?
    assert_predicate bill.reload, :paid?
  end

  test "devolução do Pix entra como estorno do pagamento: o título volta à cobrança (R284)" do
    bill, pix = paid_scenario(kind: "pix")
    fake_paid!(pix)
    @sync.call(pix)
    assert_predicate bill.reload, :paid?
    Payments::Providers::Fake.mark_refunded!(pix.external_id, 100_000)
    assert_equal :applied, @sync.call(pix).kind
    pix.reload
    assert_equal 100_000, pix.refunded_cents
    reversal = PaymentReversal.sole
    assert_equal [ 100_000, pix.payment_id ], [ reversal.amount_cents, reversal.payment_id ]
    assert_not_predicate bill.reload, :paid?
    assert_equal :ignored, @sync.call(pix).kind
    assert_equal 1, PaymentReversal.count
  end

  test "devolução parcial e depois o resto: dois estornos, cada um uma vez" do
    _bill, pix = paid_scenario(kind: "pix")
    fake_paid!(pix)
    @sync.call(pix)
    Payments::Providers::Fake.mark_refunded!(pix.external_id, 30_000)
    @sync.call(pix)
    Payments::Providers::Fake.mark_refunded!(pix.external_id, 100_000)
    @sync.call(pix)
    assert_equal [ 30_000, 70_000 ], PaymentReversal.order(:id).map(&:amount_cents)
  end

  test "devolução de instrumento sem pagamento registrado vai ao gestor e não inventa estorno" do
    customer = make_customer(@alfa)
    pix = emit(@alfa, customer, "pix", 100_000)
    fake_paid!(pix)
    @sync.call(pix)
    Payments::Providers::Fake.mark_refunded!(pix.external_id, 100_000)
    assert_equal :review, @sync.call(pix).kind
    assert_equal 0, PaymentReversal.count
  end

  test "o checkout do instrumento pago passa a pago (Checkouts.sync)" do
    bill, pix = paid_scenario(kind: "pix", amount_cents: 99_900)
    checkout = Payments::Checkouts.create(tenant: @alfa, customer: bill.customer, instruments: [ pix ], card: false, amount_cents: 99_900)
    fake_paid!(pix)
    assert_broadcasts(PaymentCheckoutChannel.broadcasting_for(checkout), 1) { @sync.call(pix) }
    assert checkout.reload.state_paid?
  end

  test "instrumento ainda não emitido no fornecedor ou de fornecedor que saiu do código: nada a conferir" do
    customer = make_customer(@alfa)
    make_account(@alfa, modality: "boleto", environment: "production")
    pending = Payments::Issuer.new.request(tenant: @alfa, kind: "boleto", amount_cents: 1_000, customer: customer, environment: "production")
    assert_equal :ignored, @sync.call(pending).kind
  end

  test "cartão não confirmado (sem identificador): o aviso traz o custom_id, a consulta confirma e o link passa a pago" do
    bill = make_bill(@alfa, number: "NF-8", amount_cents: 50_000)
    checkout = make_checkout(customer: bill.customer, amount_cents: 50_000, reference: [ "bill", bill.id ])
    Payments::Providers::Fake.fail_on(:charge_card, Payments::Providers::NetworkError.new("tempo esgotado", retry_safe: false), times: 1)
    assert_equal :unconfirmed, Payments::CardCharger.new.charge(checkout, payment_token: "TOKEN-DO-NAVEGADOR-1", installments: 1).kind
    attempt = checkout.reload.card_instruments.sole
    assert_nil attempt.external_id
    assert checkout.state_card_unconfirmed?
    # O fornecedor tinha cobrado: o falso guarda a cobrança pelo custom_id, como a Efí no painel dela.
    charged = attempt.account.adapter.charge_card(attempt.account, custom_id: attempt.custom_id, amount_cents: 50_000, installments: 1, payment_token: "TOKEN-DO-NAVEGADOR-1", payer: {})
    Payments::Providers::Fake.mark_paid!(charged.external_id)
    event = PaymentEvent.record(attempt.account, Payments::Providers::Notification.new(event_id: "N1", kind: :paid, external_id: charged.external_id, custom_id: attempt.custom_id)).first
    Payments::EventProcessor.new.run(event)
    assert_equal [ "applied", charged.external_id ], [ event.reload.state, attempt.reload.external_id ]
    assert attempt.state_paid?
    assert checkout.reload.state_paid?
    assert_predicate bill.reload, :paid?
  end

  test "nenhum instrumento de outro credor é tocado (V10): o aviso só acha instrumento da mesma conta" do
    bill, instrument = paid_scenario
    beta = tenants(:beta)
    other_customer = make_customer(beta, document: PaymentsHelper::JOAO, name: "João")
    make_channel(beta, code: "BETA-1")
    other = emit(beta, other_customer, "boleto", 100_000)
    fake_paid!(other)
    event = PaymentEvent.record(instrument.account, Payments::Providers::Notification.new(event_id: "X", kind: :paid, external_id: other.external_id)).first
    Payments::EventProcessor.new.run(event)
    assert event.reload.state_ignored?
    assert other.reload.state_active?
    assert_not_predicate bill.reload, :paid?
  end
end
