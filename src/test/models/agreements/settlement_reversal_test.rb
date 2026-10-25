require "test_helper"

# Estorno do pagamento da quitação antecipada (11, R230, AE9, AF4).
class Agreements::SettlementReversalTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    travel_day(Date.new(2026, 11, 4))
    pay_lines([ pay_line("ACD-000001-00", Date.new(2026, 11, 4), 34_366) ])
    travel_day(Date.new(2026, 11, 18))
    @quote = AgreementSettlement.calculate!(@agreement.reload, on: Date.new(2026, 11, 19), today: Date.new(2026, 11, 18))
    pay_lines([ pay_line("ACD-000001", Date.new(2026, 11, 18), @quote.amount_cents, id: "PIX-QUITA") ])
    @agreement.reload
  end

  teardown { travel_back }

  def reverse(cents)
    run_payments_import([ reversal_line("identificador_pagamento" => "PIX-QUITA", "valor" => Money.format(cents), "data_estorno" => "18/11/2026", "identificador_estorno" => "E-#{SecureRandom.hex(3)}") ], kind: "reversals", confirm: true)
  end

  test "R230: pagar o valor calculado em 18/11 quita o acordo, sem os juros do parcelamento que ainda não correram" do
    assert_predicate @agreement, :state_settled?
    assert_equal [ "paid" ], @agreement.titles.reload.map(&:status).uniq - [ "paid" ] + [ "paid" ]
    assert_equal @quote.amount_cents, Payment.find_by!(identifier: "PIX-QUITA").amount_cents
    assert_operator Abatement.where(kind: "early").sum(:amount_cents), :>, 0
  end

  test "AE9: o estorno de R$ 0,50 da quitação a mantém, porque o resto cobre o valor dentro da tolerância de R$ 1,00, e a diferença vira abatimento por tolerância" do
    reverse(50)

    assert_predicate @agreement.reload, :state_settled?
    assert_equal 50, Abatement.where(kind: "tolerance").sum(:amount_cents)
    assert_equal [ "paid" ], @agreement.titles.reload.map(&:status).uniq - [ "paid" ] + [ "paid" ]
  end

  test "R230: o estorno de R$ 100,00 desfaz a quitação: os títulos voltam com os juros cheios do parcelamento e o resto paga do mais antigo para o mais novo, com o desconto de antecipação" do
    dispensed = Abatement.where(kind: "early").sum(:amount_cents)
    reverse(10_000)

    assert_predicate @agreement.reload, :state_active_on_time?
    assert_operator Abatement.where(kind: "early").sum(:amount_cents), :<, dispensed, "os juros dispensados voltaram (linhas negativas); só a parcela paga com antecipação tem desconto"
    paid = @agreement.titles.reload.where.not(number: "ACD-000001-00")
    assert_predicate paid.first, :paid?, "o dinheiro que sobrou paga a parcela 1, a mais antiga"
    assert_equal @quote.amount_cents - 10_000, PaymentAllocation.where(payment: Payment.find_by!(identifier: "PIX-QUITA")).sum(:amount_cents)
    assert_empty @agreement.settlements.where(expired_at: nil)
  end
end
