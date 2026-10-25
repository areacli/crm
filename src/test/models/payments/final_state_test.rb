require "test_helper"

# Estado final do pagamento, tolerância de valor do pagamento direto e abatimentos (03, R46; 11, R226, R228a, N1, N3): o título dado por pago pelo credor ou pela
# tolerância fica pago, a diferença é registrada por componente, e o estorno do pagamento desfaz o abatimento.
class Payments::FinalStateTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @channel = make_channel(@alfa)
    seed_indexes!
    configure_charges(@alfa)
    @bill = make_bill(@alfa, number: "NF-2", amount_cents: 50_000, due: Date.new(2026, 9, 15))
  end

  def pay(amount, state: nil, id: "P#{SecureRandom.hex(3)}", on: "30/10/2026", bill: @bill)
    travel_to Date.new(2026, 10, 30) do
      run_payments_import([ payment_line("identificador" => id, "titulo" => bill.number, "data_pagamento" => on, "valor" => Money.format(amount), "estado_final" => state) ], confirm: true)
    end
  end

  def abated = Abatement.where(bill: @bill).group(:kind, :component).sum(:amount_cents)

  test "R226, N1: com o estado final 'quitado' o NF-2 fica pago e a diferença de R$ 19,46 é abatimento do credor" do
    import = pay(50_000, state: "quitado")

    @bill.reload
    assert_equal [ "paid", 50_000, Date.new(2026, 10, 30) ], [ @bill.status, @bill.paid_cents, @bill.paid_on ]
    assert_equal({ [ "creditor", "principal" ] => 1_946 }, abated)
    assert_equal({ "interest" => 737, "fine" => 1_004, "correction" => 205, "principal" => 48_054 }, PaymentAllocation.where(bill: @bill).group(:component).sum(:amount_cents))
    assert_equal 50_000, Payment.sole.applied_cents, "o abatimento não é dinheiro"
    assert_equal 0, Credit.where(contract: @bill.contract).sum(:amount_cents)
    assert_equal [ 1, 1_946 ], [ import.summary.dig("confirmed_effect", "abated"), import.summary.dig("confirmed_effect", "abated_cents") ]
  end

  test "R226: sem o estado final, o mesmo pagamento deixa R$ 19,46 em aberto; 'parcial' é só informativo" do
    pay(50_000, state: "parcial")

    @bill.reload
    assert_equal [ "active", 48_054 ], [ @bill.status, @bill.paid_cents ]
    assert_empty Abatement.where(bill: @bill)
    assert_equal "partial", Payment.sole.final_state
  end

  test "R226: o estado final vem antes da política de pagamento parcial ('crédito sem baixar')" do
    @alfa.setting.update!(partial_payment_policy: :credit)
    pay(50_000, state: "quitado")

    assert_equal "paid", @bill.reload.status
    assert_equal 0, Credit.where(contract: @bill.contract).sum(:amount_cents)
  end

  test "R226: valor que cobre tudo não gera abatimento nem muda com o estado final; o que passa vira crédito" do
    pay(60_000, state: "quitado")

    assert_equal "paid", @bill.reload.status
    assert_empty Abatement.where(bill: @bill)
    assert_equal 60_000 - 51_946, Credit.where(contract: @bill.contract).sum(:amount_cents)
  end

  test "R228a, N3: a tolerância de valor do pagamento direto, em reais, dá o título por pago com abatimento por tolerância" do
    @alfa.setting.update!(agreement_policies: { "tolerance_direct" => { "kind" => "cents", "value" => 2_000 } })
    pay(50_000)

    assert_equal "paid", @bill.reload.status
    assert_equal({ [ "tolerance", "principal" ] => 1_946 }, abated)
  end

  test "R228a: a tolerância em percentual incide sobre o devido do título na data do pagamento" do
    @alfa.setting.update!(agreement_policies: { "tolerance_direct" => { "kind" => "percent", "value" => 300 } }) # 3% de R$ 519,46 = R$ 15,58
    pay(50_000)
    assert_equal "active", @bill.reload.status

    other = make_bill(@alfa, number: "NF-3", amount_cents: 50_000, due: Date.new(2026, 9, 15))
    @alfa.setting.update!(agreement_policies: { "tolerance_direct" => { "kind" => "percent", "value" => 400 } }) # 4% = R$ 20,77
    pay(50_000, bill: other, id: "P-OUTRO")
    assert_equal "paid", other.reload.status
  end

  test "R228a: sem tolerância configurada (padrão zero) nada muda; acima da tolerância, a política de pagamento parcial decide" do
    @alfa.setting.update!(agreement_policies: { "tolerance_direct" => { "kind" => "cents", "value" => 1_000 } })
    pay(50_000)

    assert_equal "active", @bill.reload.status
    assert_empty Abatement.where(bill: @bill)
  end

  test "R226: o estado final prevalece sobre a tolerância (o tipo do abatimento é o do credor)" do
    @alfa.setting.update!(agreement_policies: { "tolerance_direct" => { "kind" => "cents", "value" => 2_000 } })
    pay(50_000, state: "quitado")

    assert_equal({ [ "creditor", "principal" ] => 1_946 }, abated)
  end

  test "R226: o estorno do pagamento desfaz o abatimento e o título volta a ser devido" do
    pay(50_000, state: "quitado", id: "PIX-ABATE")
    travel_to Date.new(2026, 10, 30) do
      run_payments_import([ reversal_line("identificador_pagamento" => "PIX-ABATE", "valor" => "100,00", "data_estorno" => "30/10/2026") ], kind: "reversals", confirm: true)
    end

    @bill.reload
    assert_equal "active", @bill.status
    assert_equal 0, Abatement.where(bill: @bill).sum(:amount_cents), "as linhas negativas zeram o abatimento"
    assert_equal 2, Abatement.where(bill: @bill).count
    assert_equal 48_054 - 10_000, @bill.paid_cents
  end

  test "R226: o estorno total do pagamento zera o pago e o abatimento" do
    pay(50_000, state: "quitado", id: "PIX-TOTAL")
    travel_to Date.new(2026, 10, 30) do
      run_payments_import([ reversal_line("identificador_pagamento" => "PIX-TOTAL", "valor" => "500,00", "data_estorno" => "30/10/2026") ], kind: "reversals", confirm: true)
    end

    assert_equal [ "active", 0 ], [ @bill.reload.status, @bill.paid_cents ]
    assert_equal 0, Abatement.where(bill: @bill).sum(:amount_cents)
  end

  test "PG-3: estado final fora da lista recusa a linha" do
    import = nil
    travel_to Date.new(2026, 10, 30) do
      import = run_payments_import([ payment_line("titulo" => "NF-2", "data_pagamento" => "30/10/2026", "valor" => "500,00", "estado_final" => "pago") ])
    end

    assert_equal "estado final fora da lista (quitado ou parcial)", import.rejections.sole.reason
  end

  test "R100: o histórico do título mostra o abatimento do credor" do
    pay(50_000, state: "quitado")
    events = Portfolio::BillHistory.new(@bill).events.select { |event| event.kind == :abatement }

    assert_equal [ 1_946 ], events.map(&:cents)
    assert_includes events.first.text, "do credor"
  end

  test "V10: o abatimento de um credor não aparece no outro" do
    pay(50_000, state: "quitado")

    assert_equal 0, Abatement.where(tenant: tenants(:beta)).count
    assert_equal 1, Abatement.where(tenant: @alfa).count
  end
end
