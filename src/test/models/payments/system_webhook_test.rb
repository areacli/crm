require "test_helper"

# Webhook genérico por sistema (17, R417c, R418): o evento declara o sistema como a linha da planilha; sem o campo, no credor com mais de um sistema além do
# CRM, é recusado com o motivo.
class Payments::SystemWebhookTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @channel = make_channel(@alfa)
    @secret = @channel.regenerate_webhook_secret!
    manager = SourceSystems::Manager.new(users(:joana))
    @sap = manager.create(tenant: @alfa, name: "SAP", key_kind: "natural")
    @oracle = manager.create(tenant: @alfa, name: "Oracle", key_kind: "own_id")
    @customer = Customer.create!(tenant: @alfa, document: "52998224725", name: "Maria Souza")
  end

  def system_bill(system, number:, external_id: nil)
    contract = Contract.find_or_create_by!(tenant: @alfa, source_system: system, code: "CT-#{system.name}") { |record| record.external_id = "K-1" if system.key_own_id? }
    ContractCustomer.find_or_create_by!(contract: contract, customer: @customer)
    Bill.create!(tenant: @alfa, contract: contract, customer: @customer, number: number, external_id: external_id, due_date: Date.current - 30, amount_cents: 100_000, status: :active)
  end

  def deliver(id:, **data)
    body = { id: id, type: "payment.received", data: { identifier: "PIX-W1", document: "52998224725", bill_number: "NF-1", paid_on: (Date.current - 1).iso8601, amount_cents: 100_000,
                                                       method: "pix" }.merge(data) }.to_json
    post payments_webhook_path(@channel), params: body, headers: { "CONTENT_TYPE" => "application/json", "X-Signature" => OpenSSL::HMAC.hexdigest("SHA256", @secret, body) }
    perform_enqueued_jobs
    WebhookEvent.find_by!(event_id: id).values_at(:status, :outcome).map(&:to_s)
  end

  test "R417c: o evento sem sistema, no credor com SAP e Oracle, é recusado com o motivo; com o sistema, é aplicado e o pai é o sistema declarado" do
    nf1 = system_bill(@sap, number: "NF-1")
    assert_equal [ "rejected", "sistema obrigatório: o credor tem mais de um sistema" ], deliver(id: "evt-1")
    assert_equal [ "rejected", "sistema desconhecido: Totvs" ], deliver(id: "evt-2", system: "Totvs")
    assert_equal 0, Payment.count

    assert_equal [ "applied", "título quitado" ], deliver(id: "evt-3", system: "SAP")
    assert_predicate nf1.reload, :paid?
    assert_equal [ @sap, nf1 ], [ Payment.sole.source_system, Payment.sole.bill ]
  end

  test "R417: o evento acha o título pelo id no sistema de id próprio, sem o número" do
    t77 = system_bill(@oracle, number: "NF-9", external_id: "T-77")
    assert_equal [ "applied", "título quitado" ], deliver(id: "evt-1", system: "Oracle", external_bill_id: "T-77", bill_number: "")
    assert_equal [ @oracle, t77, "T-77", "NF-9" ], Payment.sole.then { |p| [ p.source_system, p.bill, p.external_bill_id, p.bill_number ] }
  end

  test "R418: o evento que repete um pendente com outro sistema troca o sistema dele e o reavalia; com o mesmo sistema, é pagamento já registrado" do
    t100 = system_bill(@oracle, number: "NF-100", external_id: "T-100")
    status, outcome = deliver(id: "evt-1", system: "SAP", bill_number: "NF-100")
    assert_equal "applied", status
    assert_match(/pendente/, outcome)
    assert_equal [ "ignored", "pagamento já registrado" ], deliver(id: "evt-2", system: "SAP", bill_number: "NF-100")

    assert_equal [ "applied", "sistema do pagamento pendente trocado: aplicado" ], deliver(id: "evt-3", system: "Oracle", external_bill_id: "T-100", bill_number: "NF-100")
    assert_equal [ "applied", @oracle, t100 ], Payment.sole.then { |p| [ p.status, p.source_system, p.bill ] }
    assert_predicate t100.reload, :paid?
    assert_equal [ "SAP", "Oracle" ], Change.find_by!(subject_type: "payment", event: "system_changed").values_at(:before, :after)
  end
end
