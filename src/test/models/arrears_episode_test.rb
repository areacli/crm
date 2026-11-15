require "test_helper"

# Episódio de atraso (21, R434; 13, revisão 7; plano técnico da camada 23, decisões 1 a 3) e as datas de cobrança do título (decisão 2).
class ArrearsEpisodeTest < ActiveSupport::TestCase
  include SegmentsTestHelper

  setup do
    @tenant = tenants(:alfa)
    travel_to Time.zone.local(2026, 12, 7, 10) # segunda-feira
  end

  def contract_with(code, *dues, customer: nil)
    contract = Contract.create!(tenant: @tenant, code: code)
    customer ||= customer_of(@tenant, FakeData.cpf(code.hash.abs % 900 + 20))
    ContractCustomer.create!(contract: contract, customer: customer, roles: [])
    dues.each_with_index do |due, index|
      Bill.create!(tenant: @tenant, contract: contract, customer: customer, number: "#{code}-#{index}", due_date: due, amount_cents: 10_000)
    end
    contract
  end

  def refresh(subject = "contracts", on: Date.current) = ArrearsEpisode.refresh(@tenant, subject, today: on)

  def open_of(record, subject = "contracts") = ArrearsEpisode.open.find_by(tenant: @tenant, subject_type: subject, subject_id: record.id)

  def pay(bill, on: Date.current) = bill.update!(status: "paid", paid_cents: bill.amount_cents, paid_on: on)

  def revert(bill) = bill.update!(status: "active", paid_cents: 0, paid_on: nil)

  test "o título guarda o dia em que saiu de cobrança e o dia em que voltou, pelo registro e pelo conjunto" do
    contract = contract_with("C-1", Date.new(2026, 11, 20), Date.new(2026, 11, 25))
    first, second = contract.reload.then { Bill.where(contract: contract).order(:due_date).to_a }
    pay(first, on: Date.new(2026, 12, 4))
    assert_equal Date.new(2026, 12, 4), first.reload.closed_on, "o pago sai no dia do pagamento"

    travel_to Time.zone.local(2026, 12, 9, 15)
    revert(first)
    assert_equal [ nil, Date.new(2026, 12, 9) ], [ first.reload.closed_on, first.reopened_on ]

    Bill.where(id: [ first.id, second.id ]).change_status_to!("canceled")
    assert_equal [ Date.new(2026, 12, 9) ] * 2, [ first.reload.closed_on, second.reload.closed_on ]
    Bill.where(id: second.id).change_status_to!("active")
    assert_equal [ nil, Date.new(2026, 12, 9) ], [ second.reload.closed_on, second.reopened_on ]
  end

  test "o título de acordo agendado não foi cobrado e não tem data; o que já nasce pago saiu no dia do pagamento" do
    contract = contract_with("C-2")
    customer = contract.customers.first
    scheduled = Bill.create!(tenant: @tenant, contract: contract, customer: customer, number: "A-1", due_date: Date.new(2026, 12, 1), amount_cents: 5_000, status: "scheduled")
    Bill.where(id: scheduled.id).change_status_to!("canceled")
    assert_nil scheduled.reload.closed_on

    paid = Bill.create!(tenant: @tenant, contract: contract, customer: customer, number: "H-1", due_date: Date.new(2026, 10, 1), amount_cents: 5_000,
                        paid_cents: 5_000, status: "paid", paid_on: Date.new(2026, 10, 3))
    assert_equal Date.new(2026, 10, 3), paid.closed_on
  end

  test "o episódio começa no dia seguinte ao vencimento mais antigo e acaba quando o atraso acaba" do
    contract = contract_with("C-3", Date.new(2026, 11, 20), Date.new(2026, 11, 30), Date.new(2026, 12, 20))
    assert_equal 1, refresh[:opened]
    assert_equal Date.new(2026, 11, 21), open_of(contract).started_on

    Bill.where(contract: contract).where(due_date: ...Date.current).find_each { |bill| pay(bill) }
    assert_equal 1, refresh[:closed]
    assert_nil open_of(contract), "o título a vencer não é atraso"
    assert_equal Date.new(2026, 12, 6), ArrearsEpisode.find_by(subject_id: contract.id).ended_on
  end

  test "pagou na sexta e voltou a atrasar no domingo, sem nada rodar no meio: episódio novo (R434)" do
    contract = contract_with("C-4", Date.new(2026, 11, 20), Date.new(2026, 12, 5))
    travel_to Time.zone.local(2026, 12, 3, 9) # quinta
    refresh
    first = open_of(contract)
    assert_equal Date.new(2026, 11, 21), first.started_on

    pay(Bill.find_by(contract: contract, due_date: Date.new(2026, 11, 20)), on: Date.new(2026, 12, 4)) # sexta
    travel_to Time.zone.local(2026, 12, 7, 9) # segunda; o segundo título venceu no sábado e está atrasado desde domingo
    refresh
    second = open_of(contract)
    assert_not_equal first.id, second.id
    assert_equal Date.new(2026, 12, 6), second.started_on
    assert_equal Date.new(2026, 12, 3), first.reload.ended_on
  end

  test "estorno no dia seguinte ao pagamento abre episódio novo (Q6), pela tarefa diária no meio" do
    contract = contract_with("C-5", Date.new(2026, 11, 20))
    bill = Bill.find_by(contract: contract)
    travel_to Time.zone.local(2026, 12, 3, 9)
    refresh
    first = open_of(contract)
    pay(bill, on: Date.new(2026, 12, 3))

    travel_to Time.zone.local(2026, 12, 4, 5, 30) # a tarefa diária vê o dia sem atraso
    refresh
    assert_nil open_of(contract)

    travel_to Time.zone.local(2026, 12, 4, 14)
    revert(bill)
    refresh
    assert_not_equal first.id, open_of(contract).id
    assert_equal Date.new(2026, 12, 4), open_of(contract).started_on
  end

  test "estorno no mesmo dia do pagamento continua o episódio, mesmo com uma rodada no meio (decisão 3)" do
    contract = contract_with("C-6", Date.new(2026, 11, 20))
    bill = Bill.find_by(contract: contract)
    refresh
    first = open_of(contract)

    pay(bill)
    refresh
    assert_nil open_of(contract)

    revert(bill)
    assert_equal 1, refresh[:reopened]
    assert_equal first.id, open_of(contract).id
    assert_equal Date.new(2026, 11, 21), open_of(contract).started_on
  end

  test "a correção de carga que muda o vencimento não abre episódio novo" do
    contract = contract_with("C-7", Date.new(2026, 11, 20))
    refresh
    first = open_of(contract)
    Bill.find_by(contract: contract).update!(due_date: Date.new(2026, 11, 10))
    refresh
    assert_equal first.id, open_of(contract).id
    Bill.find_by(contract: contract).update!(due_date: Date.new(2026, 11, 28))
    refresh
    assert_equal first.id, open_of(contract).id, "sem dia sem atraso no meio, o início guardado fica"
  end

  test "o episódio do cliente junta os títulos de todos os contratos dele" do
    customer = customer_of(@tenant, FakeData.cpf(501))
    first = contract_with("C-8", Date.new(2026, 11, 20), customer: customer)
    contract_with("C-9", Date.new(2026, 11, 28), customer: customer)
    pay(Bill.find_by(contract: first), on: Date.new(2026, 12, 1))
    refresh("customers")
    assert_equal Date.new(2026, 11, 21), open_of(customer, "customers").started_on, "os intervalos se encostam: 21/11 a 01/12 e 29/11 em diante"
  end

  test "pago no mesmo dia em que venceu não deixa intervalo, e o episódio termina no dia anterior; o atraso seguinte é episódio novo" do
    contract = contract_with("C-12", Date.new(2026, 12, 6))
    refresh
    first = open_of(contract)
    pay(Bill.find_by(contract: contract))
    travel_to Time.zone.local(2026, 12, 8, 9)
    refresh
    assert_equal Date.new(2026, 12, 6), first.reload.ended_on
    Bill.create!(tenant: @tenant, contract: contract, customer: contract.customers.first, number: "C-12-n", due_date: Date.new(2026, 12, 7), amount_cents: 1_000)
    travel_to Time.zone.local(2026, 12, 9, 9)
    refresh
    assert_not_equal first.id, open_of(contract).id
  end

  test "o refresh restrito mexe só nos sujeitos dados" do
    one = contract_with("C-10", Date.new(2026, 11, 20))
    other = contract_with("C-11", Date.new(2026, 11, 20))
    ArrearsEpisode.refresh(@tenant, "contracts", only: [ one.id ])
    assert open_of(one)
    assert_nil open_of(other)
  end
end
