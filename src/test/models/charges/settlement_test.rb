require "test_helper"

# Baixa por componente (09 revisão 4; 11, R226 adiantada para todo título): o pagamento cobre o valor atualizado na data dele, encargos antes do
# principal, e o título só fica pago quando cobre tudo. Alocação gravada por componente; o estorno desfaz na ordem inversa.
class ChargesSettlementTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @channel = make_channel(@alfa)
    seed_indexes!
  end

  def pay(bill, amount, on:, id: "P#{SecureRandom.hex(3)}")
    travel_to TODAY.in_time_zone.change(hour: 12) do
      run_payments_import([ payment_line("identificador" => id, "titulo" => bill.number, "data_pagamento" => on.strftime("%d/%m/%Y"), "valor" => Money.format(amount)) ], confirm: true)
    end
  end

  def allocated(bill) = PaymentAllocation.where(bill: bill).group(:component).sum(:amount_cents)

  test "R226 (11): boleto de R$ 500,00 ao NF-2 em 30/10 cobre juros 7,37, multa 10,04, correção 2,05 e principal 480,54; o título fica com R$ 19,46 em aberto" do
    configure_charges(@alfa)
    bill = make_bill(@alfa, number: "NF-2", amount_cents: 50_000, due: Date.new(2026, 9, 15))
    travel_to Date.new(2026, 10, 30) do
      run_payments_import([ payment_line("titulo" => "NF-2", "data_pagamento" => "30/10/2026", "valor" => "500,00") ], confirm: true)
      bill.reload
      assert_equal({ "interest" => 737, "fine" => 1004, "correction" => 205, "principal" => 48_054 }, allocated(bill))
      assert_equal [ "active", 48_054 ], [ bill.status, bill.paid_cents ]
      assert_equal 50_000, Payment.sole.applied_cents, "o aplicado é o dinheiro todo"
      recalc_values(@alfa, today: Date.new(2026, 10, 30))
      assert_equal 1946, total_of(bill)
    end
  end

  test "R50 e R226: valor igual ao atualizado quita o título; o que passa do atualizado vira crédito do contrato" do
    configure_charges(@alfa)
    bill = make_bill(@alfa, due: DUE)
    pay(bill, 105_756 + 500, on: TODAY)
    bill.reload
    assert_equal [ "paid", 100_000, TODAY ], [ bill.status, bill.paid_cents, bill.paid_on ]
    assert_equal({ "interest" => 3211, "fine" => 2011, "correction" => 534, "principal" => 100_000 }, allocated(bill))
    assert_equal 500, Credit.where(contract: bill.contract).sum(:amount_cents)
    assert_equal 105_756, Payment.sole.applied_cents
  end

  test "R170/R226: o pagamento do valor original deixa os encargos em aberto e o título ativo (acabou o recorte da 09)" do
    configure_charges(@alfa)
    bill = make_bill(@alfa, due: DUE)
    pay(bill, 100_000, on: TODAY)
    bill.reload
    assert_equal [ "active", 94_244 ], [ bill.status, bill.paid_cents ], "juros, multa e correção (R$ 57,56) saíram antes do principal"
    assert_equal 5756, bill.balance_cents
  end

  test "R226 e M5: dois pagamentos parciais; o segundo é alocado sobre o estado atual" do
    configure_charges(@alfa, index: "none")
    bill = make_bill(@alfa, due: DUE)
    pay(bill, 40_000, on: Date.new(2026, 9, 15))
    first = allocated(bill)
    assert_equal({ "interest" => 2016, "fine" => 2000, "principal" => 35_984 }, first)
    pay(bill, 20_000, on: TODAY)
    total = allocated(bill)
    assert_equal first["fine"], total["fine"], "a multa já alocada não cresce"
    assert_equal 60_000, total.values.sum
  end

  test "R46: com a política 'crédito sem baixar', o pagamento menor que o atualizado vira crédito e o título fica como está" do
    configure_charges(@alfa)
    @alfa.setting.update!(partial_payment_policy: :credit)
    bill = make_bill(@alfa, due: DUE)
    pay(bill, 50_000, on: TODAY)
    assert_equal [ 0, 50_000 ], [ bill.reload.paid_cents, Credit.where(contract: bill.contract).sum(:amount_cents) ]
    assert_empty PaymentAllocation.where(bill: bill)
  end

  test "R46a: título retirado com 'o pagamento prevalece' continua sem encargos, baixa o principal" do
    configure_charges(@alfa)
    bill = make_bill(@alfa, due: DUE, status: :withdrawn)
    pay(bill, 100_000, on: TODAY)
    assert_equal [ "paid", { "principal" => 100_000 } ], [ bill.reload.status, allocated(bill) ]
  end

  test "credor sem regra de encargos: a baixa é só do principal, uma alocação por pagamento" do
    bill = make_bill(@alfa, due: DUE)
    pay(bill, 100_000, on: TODAY)
    assert_equal [ "paid", { "principal" => 100_000 } ], [ bill.reload.status, allocated(bill) ]
  end

  test "R226 e estorno: estornar parte do pagamento desfaz o principal primeiro e reabre o título; o estorno do resto desfaz os encargos" do
    configure_charges(@alfa)
    bill = make_bill(@alfa, due: DUE)
    pay(bill, 105_756, on: TODAY, id: "PIX-9")
    assert_equal "paid", bill.reload.status
    travel_to TODAY.in_time_zone.change(hour: 12) do
      run_payments_import([ reversal_line("identificador_pagamento" => "PIX-9", "valor" => "300,00", "data_estorno" => "21/10/2026") ], kind: "reversals", confirm: true)
    end
    bill.reload
    assert_equal [ "active", 70_000 ], [ bill.status, bill.paid_cents ]
    assert_equal 70_000, PaymentAllocation.where(bill: bill, component: "principal").sum(:amount_cents)
    assert_equal 5756, PaymentAllocation.where(bill: bill).where.not(component: "principal").sum(:amount_cents)
  end

  test "V10: o pagamento de um credor não lê nem grava alocação de outro" do
    configure_charges(@alfa)
    other = make_bill(tenants(:beta), due: DUE, document: PaymentsHelper::JOAO)
    bill = make_bill(@alfa, due: DUE)
    pay(bill, 20_000, on: TODAY)
    assert_empty PaymentAllocation.where(bill: other)
  end

  test "AN1: a regra sobe para juros de 2% depois de um pagamento parcial; o encargo até o pagamento fica pela regra antiga e a parte em aberto segue a nova" do
    configure_charges(@alfa, index: "none")
    bill = make_bill(@alfa, due: DUE)
    pay(bill, 40_000, on: Date.new(2026, 9, 15))
    assert_equal({ "interest" => 2016, "fine" => 2000, "principal" => 35_984 }, allocated(bill))
    travel_to TODAY.in_time_zone.change(hour: 9) do
      Segments::Applier.new(users(:joana)).confirm(@alfa, Segments::Proposal.current(@alfa).with_charges("charge_interest_pct" => "2").token)
    end
    recalc_values(@alfa)
    # Até 15/09 vale 1% (R$ 20,1613, já pago); de 15/09 a 21/10, 2% sobre os R$ 640,16 em aberto (R$ 15,0747): R$ 15,08 de juros em aberto.
    row = valuation_of(bill)
    assert_equal [ 1508, 0, 64_016 ], [ row.interest_cents, row.fine_cents, row.corrected_principal_cents ]
  end

  test "AN1: sem pagamento, a regra nova vale desde o vencimento (Q3)" do
    configure_charges(@alfa, index: "none")
    bill = make_bill(@alfa, due: DUE)
    travel_to TODAY.in_time_zone.change(hour: 9) do
      Segments::Applier.new(users(:joana)).confirm(@alfa, Segments::Proposal.current(@alfa).with_charges("charge_interest_pct" => "2").token)
    end
    recalc_values(@alfa)
    assert_equal round_cents(100_000 * 0.02 * (16.0 / 31 + 2 + 21.0 / 31)), valuation_of(bill).interest_cents
  end

  private
    def round_cents(value) = Charges::Calculator.round_cents(value)
end
