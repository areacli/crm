require "test_helper"

# Anonimização (07, R130 a R135, R127a, critérios de aceite): o que muda, o que fica, o que impede e o isolamento entre credores.
class AnonymizerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @gestor = users(:joana)
    @maria = make_full_customer(@alfa, code: "CT-7")
  end

  def anonymize(customer = @maria, reason: "pedido do titular, protocolo 123", document: customer.document)
    Titular::Anonymizer.on_request(customer, actor: @gestor, reason: reason, document: document)
  end

  test "R132 (critério de aceite): depois de anonimizar não se acha nenhum dado pessoal em nenhuma tabela, e os totais não mudam" do
    bills_before = Bill.where(customer_id: @maria.id).pluck(:number, :amount_cents, :paid_cents, :status, :due_date)
    paid_before = Payment.where(tenant_id: @alfa.id).sum(:applied_cents)
    assert_not_empty find_in_database(*personal_needles), "o cenário precisa conter os dados antes"

    anonymize

    assert_empty find_in_database(*personal_needles)
    assert_equal bills_before, Bill.where(customer_id: @maria.id).pluck(:number, :amount_cents, :paid_cents, :status, :due_date)
    assert_equal paid_before, Payment.where(tenant_id: @alfa.id).sum(:applied_cents)
  end

  test "R132: nome e documento viram identificador, contatos somem, acionamento e histórico trocam o texto, título perde a descrição, pagamento troca o documento" do
    anonymize
    @maria.reload

    assert_equal "Cliente anonimizado nº #{@maria.id}", @maria.name
    assert_equal "X#{@maria.id.to_s.rjust(13, '0')}", @maria.document
    assert @maria.anonymized?
    assert_empty @maria.contacts
    attempt = @maria.attempt.reload
    assert_equal [ "removido na anonimização" ] * 2, [ attempt.text, attempt.contact_used ]
    assert_nil @maria.bill.reload.description
    assert_equal @maria.document, @maria.payment.reload.document
    assert_equal [ "removido na anonimização" ] * 2, Change.where(subject_type: "customer", subject_id: @maria.id, event: "updated").pick(:before, :after)
    assert_equal [ "removido na anonimização" ] * 2, Change.where(subject_type: "bill", subject_id: @maria.bill.id, field: "description").pick(:before, :after)
  end

  test "R134: a anonimização é registrada com quem, quando, motivo, forma e o identificador novo, sem o documento" do
    anonymize

    change = Change.find_by!(subject_type: "customer", subject_id: @maria.id, event: "anonymized")
    assert_equal [ @gestor, "pedido do titular, protocolo 123", "request", "Cliente anonimizado nº #{@maria.id}" ], [ change.user, change.note, change.origin, change.after ]
  end

  test "R131: motivo e documento digitado são obrigatórios; documento de outra pessoa é recusado" do
    assert_raises(Titular::Refused) { anonymize(reason: " ") }
    error = assert_raises(Titular::Refused) { anonymize(document: "111.444.777-35") }
    assert_match(/documento digitado não é o deste cliente/, error.message)
    assert_not @maria.reload.anonymized?
    anonymize(document: "529.982.247-25")
    assert @maria.reload.anonymized?
  end

  test "R130 (critério de aceite): crédito em aberto recusa, com o valor" do
    Credit.create!(tenant: @alfa, contract: @maria.contracts.first, kind: :entry, reason: :excess, amount_cents: 5_000)

    error = assert_raises(Titular::Refused) { anonymize }
    assert_match(/não é possível anonimizar: crédito do contrato CT-7 de R\$ 50,00 em aberto/i, error.message)
    assert_not @maria.reload.anonymized?
  end

  test "R130: título ativo, título retirado com saldo e pagamento pendente com o documento impedem, cada um com o valor" do
    active = make_bill(@alfa, document: PaymentsHelper::MARIA, number: "NF-ATIVO", amount_cents: 30_000, contract_code: "CT-7")
    error = assert_raises(Titular::Refused) { anonymize }
    assert_match(/contrato CT-7 com título em aberto de R\$ 300,00/, error.message)
    active.update!(status: :withdrawn, withdrawn_at: Time.current)
    assert_match(/título retirado com saldo de R\$ 300,00/, assert_raises(Titular::Refused) { anonymize }.message)
    active.update!(status: :paid, paid_cents: 30_000, paid_on: Date.current - 400)
    Payment.create!(tenant: @alfa, channel: @maria.payment.channel, identifier: "PEND-1", document: @maria.document, bill_number: "NF-X", paid_on: Date.current,
                    amount_cents: 12_300, payment_method: "pix", status: "pending")
    assert_match(/pagamento pendente com o documento do cliente, de R\$ 123,00/, assert_raises(Titular::Refused) { anonymize }.message)
  end

  test "R130a (critério de aceite): contrato com título do outro cliente em aberto recusa, sem identificar o outro" do
    pedro = make_customer(@alfa, document: PaymentsHelper::JOAO, name: "Pedro Segredo", contract_code: "CT-7")
    Bill.where(customer_id: pedro.id).update_all(amount_cents: 30_000)
    ContractCustomer.find_or_create_by!(contract: @maria.contracts.first, customer: pedro)

    error = assert_raises(Titular::Refused) { anonymize }
    assert_match(/contrato CT-7 com título em aberto de R\$ 300,00/, error.message)
    assert_no_match(/Pedro/, error.message)
  end

  test "R132a (critério de aceite): anonimizado o contrato fechado, o outro cliente, o contrato e o histórico do contrato não mudam" do
    pedro = make_customer(@alfa, document: PaymentsHelper::JOAO, name: "Pedro Segredo", contract_code: "CT-7")
    add_contact(pedro, "phone", "(21) 91234-5678")
    Bill.where(customer_id: pedro.id).update_all(status: "paid", paid_cents: 100_000, paid_on: Date.current - 500)
    contract = @maria.contracts.first
    ContractCustomer.find_or_create_by!(contract: contract, customer: pedro).update!(roles: [ "holder" ])
    ContractCustomer.find_by!(contract: contract, customer: @maria).update!(roles: [ "holder", "financial_responsible" ])

    anonymize

    assert_equal [ "Pedro Segredo", PaymentsHelper::JOAO.delete("^0-9") ], pedro.reload.slice(:name, :document).values
    assert_equal 1, pedro.contacts.count
    assert_equal [ @maria.id, pedro.id ].sort, contract.contract_customers.pluck(:customer_id).sort
    assert_equal [ "holder", "financial_responsible" ], ContractCustomer.find_by!(contract: contract, customer: @maria).roles
  end

  test "R135 (critério de aceite): o mesmo documento numa carga depois é um cliente novo, sem histórico" do
    anonymize
    run_portfolio_import([ csv_line("documento" => PaymentsHelper::MARIA, "nome" => "Maria Souza", "contrato" => "CT-NOVO", "titulo" => "NF-2027") ], confirm: true)

    nova = Customer.find_by!(tenant: @alfa, document: PaymentsHelper::MARIA.delete("^0-9"))
    assert_not_equal @maria.id, nova.id
    assert_not nova.anonymized?
    assert_empty Change.where(subject_type: "customer", subject_id: nova.id, event: "anonymized")
    assert @maria.reload.anonymized?
  end

  test "R127a (critério de aceite): o mesmo CPF em outro credor é outro cadastro e não é tocado" do
    other = make_full_customer(@beta, code: "CT-7")

    anonymize

    assert_not other.reload.anonymized?
    assert_equal "Maria Souza", other.name
    assert_equal 2, other.contacts.count
  end

  test "R130: o cliente já anonimizado não é anonimizado outra vez, e o retido exige desfazer a retenção" do
    anonymize
    assert_raises(Titular::Refused) { anonymize(@maria.reload, document: @maria.document) }

    retida = make_full_customer(@alfa, document: PaymentsHelper::JOAO, name: "João Retido")
    Titular::Retainer.new(@gestor).retain(retida, "processo judicial")
    assert_match(/retido/, assert_raises(Titular::Refused) { anonymize(retida) }.message)
  end

  test "exceção: importação em andamento recusa a anonimização" do
    Import.create!(tenant: @alfa, user: @gestor, mode: :incremental, status: :checking, original_name: "x.csv")

    assert_match(/importação em andamento/, assert_raises(Titular::Refused) { anonymize }.message)
  end

  test "R132 (revisão 1): nome nas listas do resumo da importação, nota da divergência e motivo do estorno também são trocados" do
    import = Import.create!(tenant: @alfa, user: @gestor, mode: :incremental, status: :confirmed, original_name: "c.csv",
                            summary: { "discrepancies" => { "items" => [ { "customer" => "Maria Souza", "number" => "NF-1" } ] },
                                       "kept_by_tenant" => { "contacts" => { "items" => [ { "customer" => "Maria Souza", "value" => PHONE } ] } } })
    discrepancy = ValueDiscrepancy.create!(tenant: @alfa, bill: @maria.bill, previous_cents: 1, reported_cents: 2, allocated_cents: 1, balance_before_cents: 0, balance_after_cents: 0,
                                           effect: "record_only", policy: "keep", status: "handled", note: "Maria Souza pediu")
    reversal = PaymentReversal.create!(tenant: @alfa, channel: @maria.payment.channel, payment: @maria.payment, identifier: "EST-9", reversed_on: Date.current, amount_cents: 100, reason: "Maria Souza contestou")

    anonymize

    assert_equal "Cliente anonimizado nº #{@maria.id}", import.reload.summary.dig("discrepancies", "items", 0, "customer")
    assert_equal "removido na anonimização", import.summary.dig("kept_by_tenant", "contacts", "items", 0, "value")
    assert_equal "removido na anonimização", discrepancy.reload.note
    assert_equal "removido na anonimização", reversal.reload.reason
  end

  test "R132: o documento do pagamento pendente sem título (mesmo cancelado) e o corpo do webhook também são trocados" do
    channel = @maria.payment.channel
    Payment.create!(tenant: @alfa, channel: channel, identifier: "PEND-2", document: @maria.document, bill_number: "NF-Y", paid_on: Date.current, amount_cents: 500,
                    payment_method: "pix", status: "cancelled", reversed_cents: 500)
    WebhookEvent.create!(tenant: @alfa, channel: channel, event_id: "evt-9", payload: { "id" => "evt-9", "data" => { "document" => "529.982.247-25" } })

    anonymize

    assert_empty find_in_database("52998224725", "529.982.247-25")
  end

  test "R55b: a nota do lançamento de transferência de crédito do contrato é trocada" do
    Credit.create!(tenant: @alfa, contract: @maria.contracts.first, kind: :transfer_in, reason: :transfer, amount_cents: 100, note: "pedido de Maria Souza")
    Credit.create!(tenant: @alfa, contract: @maria.contracts.first, kind: :transfer_out, reason: :transfer, amount_cents: -100, note: "pedido de Maria Souza")

    anonymize

    assert_empty find_in_database("Maria Souza")
  end

  test "R137: lote anonimiza vários de uma vez" do
    joao = make_full_customer(@alfa, document: PaymentsHelper::JOAO, name: "João Silva")

    assert_equal 2, Titular::Anonymizer.in_batch(@alfa.id, [ @maria.id, joao.id ])

    assert_equal [ true, true ], [ @maria.reload.anonymized?, joao.reload.anonymized? ]
    assert_empty find_in_database("João Silva", "Maria Souza")
  end
end
