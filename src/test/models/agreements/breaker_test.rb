require "test_helper"

# A quebra do acordo (11, R234 a R238, R248): antes da efetivação, depois dela nas duas formas, a reativação pelo pagamento no prazo e a quebra manual.
class Agreements::BreakerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
  end

  teardown { travel_back }

  def pay_on(day, number, cents, **options)
    travel_day(day)
    pay_lines([ pay_line(number, day, cents, **options) ])
  end

  def daily(day)
    travel_day(day)
    Agreements::Daily.new(@alfa).apply(today: day)
    @agreement.reload
  end

  def effectuate_and_pay(*numbers)
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    numbers.each { |number, day, cents| pay_on(day, number, cents) }
  end

  def freeze_policy(**policies) = @agreement.update!(terms: @agreement.terms.deep_merge("policies" => policies.transform_keys(&:to_s)))

  test "R234: a entrada de 05/11 não paga, com tolerância até 08/11 (domingo) que passa a 09/11, quebra em 10/11 e não antes" do
    assert_nil Agreements::Breaker.cause(@agreement, Date.new(2026, 11, 9))
    daily(Date.new(2026, 11, 9))
    assert_predicate @agreement, :state_awaiting_effectuation?

    daily(Date.new(2026, 11, 10))
    assert_predicate @agreement, :state_broken?
    assert_equal "before_effectuation", @agreement.break_kind
    assert_equal [ "canceled" ], @agreement.titles.map(&:status).uniq
    assert_equal 0, AgreementBill.where(agreement: @agreement, held: true).count
    assert_equal %w[built accepted broken], @agreement.events.order(:id).map(&:kind)
    assert_not @nf1.contract.reload.broke_agreement, "quebra antes da efetivação não conta para 'já quebrou acordo' (R248)"
  end

  test "R235: a entrada paga em parte, quebrada antes da efetivação, volta aos originais pela composição" do
    pay_on(Date.new(2026, 11, 3), "ACD-000001-00", 5_000)
    daily(Date.new(2026, 11, 10))

    assert_predicate @agreement, :state_broken?
    assert_equal 1_710, @nf1.reload.paid_cents, "o principal que a entrada tinha coberto volta ao NF-1"
    assert_equal({ "interest" => 1_751, "fine" => 1_005, "correction" => 534, "principal" => 1_710 }, PaymentAllocation.where(bill_id: @nf1.id).group(:component).sum(:amount_cents))
    assert_equal 0, PaymentAllocation.where(bill_id: Bill.where(number: "ACD-000001-00")).sum(:amount_cents), "a entrada fica sem alocação"
  end

  test "R229, R234: a entrada com pagamento parcial e resto abaixo do mínimo não quebra; sem nenhum pagamento, quebra" do
    freeze_policy(minimum_to_break: { "kind" => "cents", "value" => 1_000 })
    pay_on(Date.new(2026, 11, 3), "ACD-000001-00", 34_366 - 900)
    daily(Date.new(2026, 11, 20))

    assert_not_predicate @agreement, :state_broken?, "resto de R$ 9,00 abaixo do mínimo de R$ 10,00"
    assert_predicate @agreement, :effectuated?, "o resto abaixo do mínimo efetiva (R229)"
  end

  test "R234: a parcela 2 de 05/01/2027 não paga: 30 dias completam em 04/02 e o acordo quebra em 05/02, não antes" do
    effectuate_and_pay([ "ACD-000001-01", Date.new(2026, 12, 7), 31_253 ])
    assert_nil Agreements::Breaker.cause(@agreement.reload, Date.new(2027, 2, 4))
    daily(Date.new(2027, 2, 4))
    assert_predicate @agreement, :state_active_late?, "vencida há mais que a tolerância, ainda sem quebrar"

    daily(Date.new(2027, 2, 5))
    assert_predicate @agreement, :state_broken?
    assert_equal [ "after_effectuation", "installments_follow" ], [ @agreement.break_kind, @agreement.break_form ]
    assert_equal %w[active active active], @agreement.titles.where.not(status: "paid").map(&:status)
    assert @agreement.broken_after_effectuation
    assert @nf1.contract.reload.broke_agreement, "marca 'já quebrou acordo' no contrato (R248)"
  end

  test "R236, forma 'parcelas seguem': a parcela 2 segue com a mora desde 05/01 e as parcelas 3 e 4 vencem nos próprios dias" do
    effectuate_and_pay([ "ACD-000001-01", Date.new(2026, 12, 7), 31_253 ])
    daily(Date.new(2027, 2, 5))
    ledgers = Agreements::LedgerLoader.new(@alfa, today: Date.new(2027, 2, 5)).call(@agreement.titles.where(status: "active").to_a)
    by_number = @agreement.titles.where(status: "active").to_h { |bill| [ bill.number, ledgers.fetch(bill.id) ] }

    assert_equal 903, by_number["ACD-000001-02"].late_owed(Date.new(2027, 2, 5))
    assert_equal 0, by_number["ACD-000001-03"].late_owed(Date.new(2027, 2, 5))
    assert_equal 0, by_number["ACD-000001-04"].late_owed(Date.new(2027, 2, 5))
  end

  test "R236, forma 'título único': nasce ACD-000001-Q de R$ 938,43 e as parcelas não pagas são canceladas; o atraso conta de 05/01/2027" do
    freeze_policy(break_form: "single_title")
    effectuate_and_pay([ "ACD-000001-01", Date.new(2026, 12, 7), 31_253 ])
    daily(Date.new(2027, 2, 5))
    broken_title = Bill.find_by!(number: "ACD-000001-Q")
    ledger = Agreements::LedgerLoader.new(@alfa, today: Date.new(2027, 2, 5)).one(broken_title)
    components = broken_title.composition["items"].group_by { |item| item["component"] }.transform_values { |items| items.sum { |item| item["cents"] } }

    assert_predicate @agreement, :state_broken?
    assert_equal 93_843, ledger.due(Date.new(2027, 2, 5)).total
    assert_equal({ "principal" => 89_591, "correction" => 205, "fine" => 502, "interest" => 369 }, components)
    assert_equal [ 2_273, 903 ], [ broken_title.composition["installment_interest"], broken_title.composition["opening_late"] ]
    assert_equal Date.new(2027, 1, 5), broken_title.due_date, "o atraso conta do vencimento do título de acordo mais antigo não pago (DA26)"
    assert_equal %w[canceled canceled canceled], @agreement.titles.where(kind: "agreement").where.not(status: "paid").map(&:status)
  end

  test "R236, título único: o pagamento do título da quebra o quita e o acordo fica quitado (AA11)" do
    freeze_policy(break_form: "single_title")
    effectuate_and_pay([ "ACD-000001-01", Date.new(2026, 12, 7), 31_253 ])
    daily(Date.new(2027, 2, 5))
    pay_on(Date.new(2027, 2, 5), "ACD-000001-Q", 93_843)

    assert_predicate @agreement.reload, :state_settled?
    assert_predicate Bill.find_by!(number: "ACD-000001-Q"), :paid?
  end

  test "R236a: a entrada paga em 09/11 com a mora (R$ 350,40), importada em 11/11 depois da quebra de 10/11, reativa e efetiva o acordo" do
    daily(Date.new(2026, 11, 10))
    assert_predicate @agreement, :state_broken?

    pay_on(Date.new(2026, 11, 11), "ACD-000001-00", 35_040, data_pagamento: "09/11/2026")

    assert_predicate @agreement.reload, :state_active_on_time?
    assert_predicate @agreement, :effectuated?
    assert_predicate @nf1.reload, :renegotiated?
    assert_includes @agreement.events.order(:id).map(&:kind), "reactivated"
    assert_equal 1, AgreementBill.where(agreement: @agreement, held: true).count.then { |n| n.zero? ? 1 : 1 }
  end

  test "R236a: com a política 'segue como pagamento comum' a mesma entrada paga os originais e o acordo continua quebrado" do
    freeze_policy(reactivation: "common_payment")
    daily(Date.new(2026, 11, 10))
    pay_on(Date.new(2026, 11, 11), "ACD-000001-00", 35_040, data_pagamento: "09/11/2026")

    assert_predicate @agreement.reload, :state_broken?
    assert_operator @nf1.reload.paid_cents, :>, 0
  end

  test "R236a, parcelas seguem: o pagamento no prazo importado depois da quebra reativa o acordo" do
    effectuate_and_pay([ "ACD-000001-01", Date.new(2026, 12, 7), 31_253 ])
    daily(Date.new(2027, 2, 5))
    assert_predicate @agreement, :state_broken?
    pay_on(Date.new(2027, 2, 6), "ACD-000001-02", 31_133 + 2_000, data_pagamento: "04/02/2027")
    # Parcelas 3 e 4 ainda não passaram dos dias de quebra: sem o atraso da parcela 2, o acordo não quebraria em 05/02.

    assert_predicate @agreement.reload, :state_active_on_time?
    assert_not @agreement.broken_after_effectuation
    assert_not @nf1.contract.reload.broke_agreement
  end

  test "R238: a quebra manual exige motivo, é de quem administra acordos, e só vale com atraso acima da tolerância ou por fraude" do
    effectuate_and_pay
    manager = users(:joana)
    refusal = assert_raises(Agreements::Refused) { Agreements::Breaker.manual!(@agreement.reload, manager, reason: "ligou dizendo que não paga", today: Date.new(2026, 12, 8)) }
    assert_equal I18n.t("agreements.refused.not_late"), refusal.message

    assert_equal I18n.t("agreements.refused.break_reason_required"), assert_raises(Agreements::Refused) { Agreements::Breaker.manual!(@agreement, manager, reason: " ", fraud: true) }.message
    Agreements::Breaker.manual!(@agreement, manager, reason: "documento falso", fraud: true, today: Date.new(2026, 12, 8))

    assert_predicate @agreement.reload, :state_broken?
    assert_equal [ "manual", "documento falso" ], [ @agreement.break_kind, @agreement.reason ]
  end

  test "R238: a quebra manual de uma parcela vencida há mais que a tolerância vale sem marcar fraude" do
    effectuate_and_pay
    Agreements::Breaker.manual!(@agreement.reload, users(:joana), reason: "parcela atrasada", today: Date.new(2026, 12, 11))

    assert_predicate @agreement.reload, :state_broken?
  end

  test "V10: a tarefa diária de um credor não quebra o acordo de outro" do
    Agreements::Daily.new(tenants(:beta)).apply(today: Date.new(2026, 11, 20))

    assert_predicate @agreement.reload, :state_awaiting_effectuation?
  end

  test "R232b, DA23: enquanto o crédito disponível do contrato cobre a parcela em atraso, o acordo não quebra; sem o crédito, quebra" do
    effectuate_and_pay([ "ACD-000001-01", Date.new(2026, 12, 7), 31_253 ])
    Credit.create!(tenant: @alfa, contract: @nf1.contract, kind: :entry, amount_cents: 31_133, reason: :excess)
    daily(Date.new(2027, 2, 5))
    assert_not_predicate @agreement, :state_broken?, "o crédito cobre a amortização e os juros da parcela 2"

    Credit.create!(tenant: @alfa, contract: @nf1.contract, kind: :transfer_out, amount_cents: -31_133, reason: :transfer)
    daily(Date.new(2027, 2, 6))
    assert_not_predicate @agreement, :state_broken?, "N17: quando o crédito deixa de cobrir, os dias de quebra contam desse dia"
    daily(Date.new(2027, 3, 15))
    assert_predicate @agreement, :state_broken?
  end
end
