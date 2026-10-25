require "test_helper"

# Critérios de aceite da especificação 11 que as etapas 5 e 6 fecham (R229, R232b, R233, R239), com os números do texto.
class Agreements::AcceptanceCriteriaTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    @gestor = users(:joana)
  end

  teardown { travel_back }

  def pay(day, number, cents, id: "PIX-#{SecureRandom.hex(3)}")
    travel_day(day)
    pay_lines([ pay_line(number, day, cents, id: id) ])
  end

  def reverse(day, id, cents)
    travel_day(day)
    run_payments_import([ reversal_line("identificador_pagamento" => id, "valor" => Money.format(cents), "data_estorno" => day.strftime("%d/%m/%Y"), "identificador_estorno" => "E-#{SecureRandom.hex(3)}") ], kind: "reversals", confirm: true)
  end

  def title(number) = Bill.find_by!(number: number).reload

  test "R239: reversão de 40 dias: a parcela 2 retoma os 20 dias de atraso, a 3 conta da desistência e o acordo não quebra no dia seguinte" do
    pay(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    pay(Date.new(2026, 12, 7), "ACD-000001-01", 31_253)
    Agreements::Reversion.new(@gestor).open!(@agreement.reload, "erro", today: Date.new(2027, 1, 25)) # a parcela 2 venceu em 05/01: 20 dias de atraso
    Agreements::Reversion.new(@gestor).desist!(@agreement.reload, today: Date.new(2027, 3, 6))      # 40 dias depois; a parcela 3 (05/02) venceu durante a marca

    @agreement.reload
    parcel2 = title("ACD-000001-02")
    parcel3 = title("ACD-000001-03")
    # A parcela 2 vencida há 20 dias na abertura tem mais 10 dias de quebra a contar de 06/03; a 3 conta 30 dias da desistência.
    assert_nil Agreements::Breaker.cause(@agreement, Date.new(2027, 3, 7)), "o acordo não quebra no dia seguinte à desistência"
    assert_equal Date.new(2027, 3, 6), @agreement.counting_due(parcel3.due_date), "a parcela vencida durante a marca conta da desistência"
    assert_equal Date.new(2027, 1, 5) + 40, @agreement.counting_due(parcel2.due_date), "a vencida antes da marca retoma de onde parou"
    assert_equal Date.new(2027, 3, 16), @agreement.deadline_for(parcel2, 30), "mais 10 dias, a contar da desistência"
    assert_equal "installment", Agreements::Breaker.cause(@agreement, Date.new(2027, 3, 20))
  end

  test "DA8: o pagamento com o número do título renegociado vira crédito do contrato, e o estorno dele reduz o crédito sem criar título de estorno" do
    pay(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    pay(Date.new(2026, 11, 10), "NF-1", 30_000, id: "PIX-NF1")
    assert_equal 30_000, @nf1.contract.credit_cents
    reverse(Date.new(2026, 11, 12), "PIX-NF1", 30_000)

    assert_equal 0, @nf1.contract.credit_cents
    assert_equal 0, Bill.where(kind: "reversal").count
    assert_predicate @nf1.reload, :renegotiated?
  end

  test "R229: o pagamento estornado por inteiro não conta como vigente: a parcela passa dos dias de quebra e o acordo quebra, sem abatimento por mínimo" do
    @agreement.update!(terms: @agreement.terms.deep_merge("policies" => { "minimum_to_break" => { "kind" => "cents", "value" => 1_000 } }))
    pay(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    pay(Date.new(2026, 12, 7), "ACD-000001-01", 31_253)
    pay(Date.new(2027, 1, 5), "ACD-000001-02", 31_133, id: "PIX-P2")
    reverse(Date.new(2027, 1, 6), "PIX-P2", 31_133)
    travel_day(Date.new(2027, 3, 1))
    Agreements::Daily.new(@alfa).apply(today: Date.new(2027, 3, 1))

    assert_predicate @agreement.reload, :state_broken?
    assert_equal 0, Abatement.where(kind: "minimum").count
  end

  test "R232b, R233: na opção 'aplica antes de quebrar' a tarefa paga o título de estorno vencido com o crédito, e R$ 456,34 seguem disponíveis" do
    @alfa.setting.update!(agreement_policies: { "credit_and_break" => "before_break" })
    pay(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    extra = Agreements::ReversalTitles.create!(@agreement.reload, items: [ { "bill_id" => @nf1.id, "component" => "principal", "cents" => 4_366 } ], contract: @nf1.contract,
                                               action_on: Date.new(2026, 11, 5), processed_on: Date.new(2026, 11, 5))
    Credit.create!(tenant: @alfa, contract: @nf1.contract, kind: :entry, amount_cents: 50_000, reason: :excess, occurred_at: Time.zone.parse("2026-11-01 10:00"))
    travel_day(extra.due_date + 1)
    Agreements::Daily.new(@alfa).apply(today: Date.current)

    assert_predicate extra.reload, :paid?
    assert_equal 50_000 - 4_366, @nf1.contract.credit_cents
  end

  test "R239: acordo em reversão não aceita calcular quitação nem quebra manual, e as propostas vigentes sobre os títulos foram canceladas na abertura" do
    pay(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    Agreements::Reversion.new(@gestor).open!(@agreement.reload, "erro")
    policy = AgreementPolicy.new(@gestor, @agreement.reload)
    assert_not policy.settle?
    assert_not policy.break?
    assert policy.conclude?
    assert_not policy.revert?
  end
end
