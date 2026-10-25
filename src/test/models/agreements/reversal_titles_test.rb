require "test_helper"

# O título de estorno (11, R233, AH1, AI2, AI3, AJ2, AJ4): numeração, pagamento pelo número, "Usar crédito", encargos só sobre principal e correção e fora do acordo.
class Agreements::ReversalTitlesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @alfa.setting.update!(agreement_policies: { "credit_entry" => "rebate" })
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2 = agreement_scenario(@alfa)
    make_channel(@alfa)
    pago = make_bill(@alfa, number: "NF-0", contract_code: "CT-1", amount_cents: 10_000, status: :paid, document: PaymentsHelper::MARIA)
    pago.update_columns(paid_cents: 10_000)
    travel_day(Date.new(2026, 10, 20))
    pay_lines([ pay_line("NF-0", Date.new(2026, 10, 20), 4_366, id: "PIX-CREDITO") ])
    travel_day(AGREEMENT_DAY)
    @agreement = create_proposal(@customer, [ @nf1.reload, @nf2.reload ], credit: 4_366)
    accept_proposal(@agreement, @customer)
    travel_day(Date.new(2026, 11, 4))
    pay_lines([ pay_line("ACD-000001-00", Date.new(2026, 11, 4), @agreement.reload.down_payment_cents, id: "PIX-ENTRADA") ])
    travel_day(Date.new(2026, 11, 20))
    run_payments_import([ reversal_line("identificador_pagamento" => "PIX-CREDITO", "valor" => "43,66", "data_estorno" => "20/11/2026", "identificador_estorno" => "E1") ], kind: "reversals", confirm: true)
    @extra = Bill.find_by!(number: "ACD-000001-E1")
  end

  teardown { travel_back }

  def ledger(on) = Agreements::LedgerLoader.new(@alfa, today: on).one(@extra.reload)

  test "AJ2: o título de estorno é comum do cliente, fora do acordo: não entra em titles, não quebra e o acordo não muda" do
    assert_not_includes @agreement.titles.pluck(:id), @extra.id
    assert_equal [ @extra.id ], @agreement.reversal_titles.pluck(:id)
    assert_nil Agreements::Breaker.cause(@agreement.reload, Date.new(2026, 12, 1)), "o título de estorno nunca quebra o acordo"
  end

  test "AI3: depois do vencimento só o principal e a correção têm encargos, sem multa nova" do
    on = @extra.due_date + 30
    breakdown = ledger(on).late_breakdown(on)
    assert_equal 0, breakdown.fetch("fine", 0)
    assert_operator breakdown.fetch("interest", 0), :>, 0
    # a base é o principal de R$ 10,76 e a correção de R$ 5,34 (R$ 16,10): 30 dias a 1% ao mês, ÷ 30 por dia = R$ 0,16
    assert_equal 16, breakdown.fetch("interest")
  end

  test "R233: o pagamento com o número do título de estorno paga o próprio título, e o excedente vira crédito do contrato" do
    travel_day(Date.new(2026, 11, 25))
    pay_lines([ pay_line("ACD-000001-E1", Date.new(2026, 11, 25), 5_000, id: "PIX-E1") ])

    assert_predicate @extra.reload, :paid?
    assert_equal 5_000 - 4_366, @nf1.contract.credit_cents
  end

  test "R231, AJ4: o pagamento com o número do acordo sem sufixo, no acordo quitado ou depois dos títulos dele, paga o título de estorno" do
    travel_day(Date.new(2026, 12, 7))
    pay_lines([ pay_line("ACD-000001", Date.new(2026, 12, 7), 200_000, id: "PIX-NUM") ])

    assert_equal [ "paid" ], @agreement.titles.reload.map(&:status).uniq
    assert_predicate title("ACD-000001-01"), :paid?
    assert_predicate @extra.reload, :paid?, "depois dos títulos do acordo, o título de estorno numerado por ele"
  end

  test "AI2, R232b: 'Usar crédito' paga o título de estorno com o crédito disponível do contrato, sem reativar nada" do
    Credit.create!(tenant: @alfa, contract: @nf1.contract, kind: :entry, amount_cents: 3_000, reason: :excess, occurred_at: Time.current)
    outcome = Agreements::CreditOnBill.use!(@extra, 3_000, users(:joana))

    assert_equal 3_000, outcome.applied
    assert_equal 3_000, @extra.reload.paid_cents
    assert_equal 0, @nf1.contract.credit_cents
    assert_raises(Agreements::Refused) { Agreements::CreditOnBill.use!(@extra, 5_000, users(:joana)) }
    assert_raises(Agreements::Refused, "em título comum, não (AI2)") { Agreements::CreditOnBill.use!(@nf1, 100, users(:joana)) }
  end

  test "R239, AG8: a reversão do acordo cancela o título de estorno da origem do crédito e tira o valor original do crédito que volta disponível" do
    Agreements::Reversion.new(users(:joana)).open!(@agreement.reload, "erro")
    Agreements::Reversion.new(users(:joana)).conclude!(@agreement.reload)

    assert_predicate @extra.reload, :canceled?
    assert_equal 0, @nf1.contract.credit_cents, "o crédito usado de R$ 43,66 vem do título de estorno: não volta disponível"
  end

  def title(number) = Bill.find_by!(number: number).reload
end
