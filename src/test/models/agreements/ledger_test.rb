require "test_helper"

# O que um título de acordo deve e como um pagamento o cobre (11, R227, R228, R228a, R229, DA35), com os números da especificação ao centavo.
class Agreements::LedgerTest < ActiveSupport::TestCase
  RULE = Charges::AgreementRule.new(0.02, 0.01, "simple", "thirty", "corrected", "", 0.0)

  def title(due:, items:, interest: 0, period_days: 30, **composition)
    Bill.new(due_date: due, amount_cents: items.sum { |item| item[2] } + interest, kind: "agreement",
             composition: { "items" => items.map { |bill, component, cents| { "bill_id" => bill, "component" => component, "cents" => cents } },
                            "installment_interest" => interest, "period_days" => period_days, "accrues_from" => due.iso8601, "fine" => true }.merge(composition.stringify_keys))
  end

  def ledger(bill, events: [], **options) = Agreements::Ledger.new(bill, rule: RULE, events: events, **options)

  # A parcela 2 do exemplo: vence em 05/01/2027, R$ 297,73 de principal do NF-1 e R$ 13,60 de juros do parcelamento.
  def parcel2 = title(due: Date.new(2027, 1, 5), items: [ [ 1, "principal", 29_773 ] ], interest: 1_360, period_days: 29)

  def event(date, parts, cash: true) = Agreements::Ledger::Event.new(date, parts, cash)

  test "R227, R228: a parcela 2 paga em 20/01 deve a mora de R$ 7,44 (multa R$ 5,95 e juros R$ 1,49), os juros do parcelamento e a amortização: R$ 318,77" do
    due = ledger(parcel2).due(Date.new(2027, 1, 20))

    assert_equal({ "late" => 744, "installment_interest" => 1_360, "principal" => 29_773 }, due.parts)
    assert_equal 31_877, due.total
    assert_equal({ "interest" => 149, "fine" => 595 }, ledger(parcel2).late_breakdown(Date.new(2027, 1, 20)))
  end

  test "R227: no vencimento a parcela deve o valor de face; um dia antes, com o desconto dos juros; um dia depois, a multa e um dia de juros" do
    assert_equal 31_133, ledger(parcel2).due(Date.new(2027, 1, 5)).total
    assert_equal 31_133 - 47, ledger(parcel2).due(Date.new(2027, 1, 4)).total, "um dia antes: R$ 13,60 x 1/29 de desconto dos juros (DA35)"
    assert_equal 31_133 + 595 + 10, ledger(parcel2).due(Date.new(2027, 1, 6)).total
  end

  test "R229, M6: o pagamento do valor de face 15 dias depois cobre a mora e os juros e deixa R$ 7,44 de amortização, que segue com juros de atraso sem multa nova" do
    result = Agreements::TitlePayment.call(ledger(parcel2), date: Date.new(2027, 1, 20), amount: 31_133)

    assert_equal({ "late" => 744, "installment_interest" => 1_360, "principal" => 29_029 }, result.parts)
    assert_not result.settled

    after = ledger(parcel2, events: [ event(Date.new(2027, 1, 20), result.parts) ])
    assert_equal 744, after.principal_remaining
    due = after.due(Date.new(2027, 2, 19)) # 30 dias depois: juros de 30 dias sobre R$ 7,44, sem multa nova
    assert_equal({ "late" => 7, "principal" => 744 }, due.parts)
  end

  test "R228a: o boleto de R$ 318,70 na parcela 2 deixa o título pago, com R$ 0,07 de abatimento por tolerância (R$ 1,00)" do
    result = Agreements::TitlePayment.call(ledger(parcel2), date: Date.new(2027, 1, 20), amount: 31_870, tolerance: { "kind" => "cents", "value" => 100 })

    assert_predicate result, :settled
    assert_equal [ [ "tolerance", { "principal" => 7 } ] ], result.abatements
    assert_equal 31_870, result.applied
    assert_equal 29_773 - 7, result.parts["principal"]
    assert_equal 0, result.excess
  end

  test "R228a: a tolerância em percentual incide sobre o devido do título e o valor acima da tolerância não quita" do
    assert_predicate Agreements::TitlePayment.call(ledger(parcel2), date: Date.new(2027, 1, 5), amount: 31_133 - 311, tolerance: { "kind" => "percent", "value" => 100 }), :settled
    assert_not Agreements::TitlePayment.call(ledger(parcel2), date: Date.new(2027, 1, 5), amount: 31_133 - 312, tolerance: { "kind" => "percent", "value" => 100 }).settled
  end

  test "R226, N1: com o estado final 'quitado' o título fica pago e a diferença é abatimento do credor, a partir do principal" do
    result = Agreements::TitlePayment.call(ledger(parcel2), date: Date.new(2027, 1, 5), amount: 20_000, final_state: "settled")

    assert_predicate result, :settled
    assert_equal [ [ "creditor", { "principal" => 11_133 } ] ], result.abatements
    assert_equal({ "installment_interest" => 1_360, "principal" => 18_640 }, result.parts)
  end

  test "R227, DA35: a parcela 1 de R$ 312,53 paga três dias antes tem R$ 1,80 de desconto dos juros (19,20 x 3/32): R$ 310,73" do
    first = title(due: Date.new(2026, 12, 7), items: [ [ 1, "principal", 29_333 ] ], interest: 1_920, period_days: 32)
    due = ledger(first).due(Date.new(2026, 12, 4))

    assert_equal 180, due.early
    assert_equal 31_073, due.total

    result = Agreements::TitlePayment.call(ledger(first), date: Date.new(2026, 12, 4), amount: 31_073)
    assert_predicate result, :settled
    assert_equal [ [ "early", { "installment_interest" => 180 } ] ], result.abatements
    assert_equal 31_253, result.face_covered, "a face inteira do título fica coberta: o dinheiro mais o desconto"
  end

  test "DA35: com a política 'valor cheio' o título custa o valor cheio antes do vencimento" do
    first = title(due: Date.new(2026, 12, 7), items: [ [ 1, "principal", 29_333 ] ], interest: 1_920, period_days: 32)

    assert_equal 31_253, ledger(first, early_discount: false).due(Date.new(2026, 12, 4)).total
  end

  test "R227: o excedente do pagamento fica fora do título (a DA9 decide o destino) e o título pago não deve mais nada" do
    result = Agreements::TitlePayment.call(ledger(parcel2), date: Date.new(2027, 1, 5), amount: 35_000)

    assert_predicate result, :settled
    assert_equal 35_000 - 31_133, result.excess
    paid = ledger(parcel2, events: [ event(Date.new(2027, 1, 5), result.parts) ])
    assert_equal 0, paid.due(Date.new(2027, 3, 1)).total.then { |total| total - paid.late_owed(Date.new(2027, 3, 1)) }
  end

  test "R236: o título da quebra do exemplo vale R$ 938,43 (com a mora herdada de R$ 9,03) e os encargos de atraso seguem desde a quebra, sem multa nova" do
    broken = title(due: Date.new(2027, 2, 5), items: [ [ 1, "principal", 89_591 ], [ 1, "correction", 205 ], [ 1, "fine", 502 ], [ 1, "interest", 369 ] ], interest: 2_273,
                   opening_late: 903, accrues_from: "2027-02-05", fine: false)
    ledger = ledger(broken)

    assert_equal 93_843, ledger.due(Date.new(2027, 2, 5)).total
    assert_equal({ "late" => 903, "installment_interest" => 2_273 }, ledger.due(Date.new(2027, 2, 5)).parts.slice("late", "installment_interest"))
    # 30 dias depois: juros de 1% sobre principal e correção (R$ 897,96), sem multa nova.
    assert_equal 903 + 898, ledger.due(Date.new(2027, 3, 7)).late
  end

  test "R229: o título sem pagamento vigente não tem 'pagamento'; o abatimento não conta como dinheiro" do
    assert_not ledger(parcel2).paid_any?
    assert_not ledger(parcel2, events: [ event(Date.new(2027, 1, 5), { "principal" => 5 }, cash: false) ]).paid_any?
    assert ledger(parcel2, events: [ event(Date.new(2027, 1, 5), { "principal" => 5 }) ]).paid_any?
  end

  test "R230: o saldo da quitação antecipada tem a amortização, os juros do parcelamento já corridos e a mora, sem os juros futuros" do
    first = title(due: Date.new(2026, 12, 7), items: [ [ 1, "principal", 29_333 ] ], interest: 1_920, period_days: 32)
    # 16 dias depois da entrada: metade do período corrido, metade dos juros do parcelamento.
    assert_equal 29_333 + 960, ledger(first).balance(Date.new(2026, 11, 21))
    assert_equal 29_333 + 1_920, ledger(first).balance(Date.new(2026, 12, 7))
    assert_equal 29_333, ledger(first).balance(Date.new(2026, 10, 1))
  end
end
