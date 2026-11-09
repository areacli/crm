require "test_helper"

# Simulação do acordo (11, R211 a R216) com a Maria da especificação, ao centavo.
class Agreements::SimulationTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2 = agreement_scenario(@alfa)
  end

  teardown { travel_back }

  test "R211, R212: a base de R$ 1.579,93, os descontos de 50% na multa e nos juros e o valor do acordo de R$ 1.543,66" do
    quote = simulate_agreement(@customer, [ @nf1, @nf2 ])

    assert_nil quote.error
    assert_equal 157_993, quote.base_cents
    assert_equal({ "principal" => 150_000, "correction" => 739, "fine" => 3_015, "interest" => 4_239 }, quote.rows.map(&:base).each_with_object(Hash.new(0)) { |base, sum| base.each { |k, v| sum[k] += v } })
    first, second = quote.rows
    assert_equal({ "fine" => 1_006, "interest" => 1_751 }, first.discount)
    assert_equal({ "fine" => 502, "interest" => 368 }, second.discount)
    assert_equal 1_508 + 2_119, quote.discount_cents
    assert_equal 154_366, quote.value_cents
    assert_equal [ 103_290, 51_076 ], quote.rows.map(&:value)
    assert_equal 154_366, quote.net_cents
  end

  test "R213, R214: a entrada de R$ 343,66 em 05/11 e quatro parcelas Price no dia 5, a primeira em 07/12 (05/12 é sábado)" do
    quote = simulate_agreement(@customer, [ @nf1, @nf2 ])

    assert_equal Date.new(2026, 11, 5), quote.down_payment_on
    assert_equal [ Date.new(2026, 12, 7), Date.new(2027, 1, 5), Date.new(2027, 2, 5), Date.new(2027, 3, 5) ], quote.installments.map(&:due)
    assert_equal [ 31_253, 31_133, 31_133, 31_134 ], quote.installments.map(&:amount_cents)
    assert_equal [ 1_920, 1_360, 913, 460 ], quote.installments.map(&:interest_cents)
    assert_equal [ 29_333, 29_773, 30_220, 30_674 ], quote.installments.map(&:amortization_cents)
    assert_equal 4_653, quote.interest_cents
    assert_equal 120_000, quote.installments.sum(&:amortization_cents)
    assert_equal 159_019, quote.total_cents
    assert_equal BigDecimal("19.5618"), quote.effective_annual_pct
  end

  test "R214: SAC a 1,5% com o primeiro período de 32 dias e sem juros com a diferença de centavos na última" do
    @alfa.setting.update!(installment_method: "sac")
    sac = simulate_agreement(@customer, [ @nf1, @nf2 ])
    assert_equal [ 31_920, 31_350, 30_900, 30_450 ], sac.installments.map(&:amount_cents)

    @alfa.setting.update!(installment_method: "none")
    plain = simulate_agreement(@customer, [ @nf1, @nf2 ], installments: 3, down: 34_366)
    assert_equal [ 40_000, 40_000, 40_000 ], plain.installments.map(&:amount_cents)
    odd = simulate_agreement(@customer, [ @nf1, @nf2 ], installments: 7, down: 94_366)
    assert_equal 60_000, odd.installments.sum(&:amount_cents)
  end

  test "R214, N15: com a prestação recalculada, as parcelas ficam iguais" do
    @alfa.setting.update!(agreement_policies: { "first_period" => "recalculated" })
    quote = simulate_agreement(@customer, [ @nf1, @nf2 ])

    assert_equal 120_000, quote.installments.sum(&:amortization_cents)
    assert_equal 1_920, quote.installments.first.interest_cents
    assert_in_delta quote.installments[0].amount_cents, quote.installments[1].amount_cents, 1
    assert_nil quote.error
  end

  test "R216: dentro dos limites do Operador (metade) a proposta nasce aprovada; com 100% de desconto na multa, pendente" do
    assert_equal "approved", simulate_agreement(@customer, [ @nf1, @nf2 ]).status
    pending = simulate_agreement(@customer, [ @nf1, @nf2 ], discounts: { "fine" => 10_000, "interest" => 5_000 })

    assert_equal "pending", pending.status
    assert_nil pending.error
    assert_equal "approved", simulate_agreement(@customer, [ @nf1, @nf2 ], discounts: { "fine" => 10_000, "interest" => 5_000 }, user: users(:joana)).status
  end

  test "revisão 12: desconto acima do teto do item não é recusado, e o limite do perfil decide" do
    principal = simulate_agreement(@customer, [ @nf1, @nf2 ], discounts: { "principal" => 500 })
    assert_nil principal.error
    assert_equal "pending", principal.status

    fees = simulate_agreement(@customer, [ @nf1, @nf2 ], discounts: { "fees" => 6_000 })
    assert_nil fees.error
    assert_equal "pending", fees.status

    assert_equal I18n.t("agreements.refused.discount_range"), simulate_agreement(@customer, [ @nf1, @nf2 ], discounts: { "fine" => 10_100 }).error
  end

  test "revisão 12: zero parcelas é parcela única, sem entrada, no valor do acordo" do
    quote = simulate_agreement(@customer, [ @nf1, @nf2 ], installments: 0, down: nil)
    assert_nil quote.error
    assert_equal "cash", quote.mode
    assert_equal 1, quote.schedule.size
    assert_equal quote.value_cents, quote.schedule.first.amount_cents
    assert_equal quote.value_cents, quote.total_cents
    assert_equal "cash", Agreements::FormParams.input({ installments: "0", bill_ids: [ @nf1.id ] }.with_indifferent_access).mode
    assert_equal "installments", Agreements::FormParams.input({ installments: "3", bill_ids: [ @nf1.id ] }.with_indifferent_access).mode
  end

  test "revisão 12: a soma das parcelas nunca fica abaixo da dívida, nem com honorários recalculados ou o dia recusado" do
    Tier.catch_all_of(@alfa).update!(fees_pct: 10, fees_in_contract: true)
    recalc_values(@alfa, today: AGREEMENT_DAY)
    [ { installments: 0, down: nil }, { installments: 1, down: nil }, { installments: 6, down: nil }, { installments: 4, day: 0 } ].each do |caso|
      quote = simulate_agreement(@customer, [ @nf1, @nf2 ], discounts: { "fine" => 5_000, "interest" => 5_000 }, **caso)
      assert_operator quote.base_cents, :>, quote.rows.sum { |row| row.after.values.sum } + 2_000, "o desconto precisa existir"
      assert_equal quote.value_cents, quote.net_cents, caso.inspect
      assert_operator quote.schedule.sum(&:amount_cents), :>=, quote.value_cents, caso.inspect
      assert_equal quote.base_cents - quote.discount_cents, quote.value_cents
    end
  end

  test "R215: parcelas acima do máximo e parcela abaixo da mínima" do
    @alfa.setting.update!(installment_method: "price")
    assert_equal I18n.t("agreements.refused.installments_above", max: 12), simulate_agreement(@customer, [ @nf1, @nf2 ], installments: 13).error
    ok = simulate_agreement(@customer, [ @nf1, @nf2 ], down: 94_366, installments: 6)
    assert_nil ok.error
    small = simulate_agreement(@customer, [ @nf1, @nf2 ], down: 94_366, installments: 7)
    assert_equal I18n.t("agreements.refused.installment_minimum", min: "100,00"), small.error
  end

  test "R215: entrada abaixo da mínima, igual ao valor líquido no parcelado e fora do prazo" do
    assert_equal I18n.t("agreements.refused.down_minimum", pct: 10, min: "154,37"), simulate_agreement(@customer, [ @nf1, @nf2 ], down: 15_000).error
    assert_equal I18n.t("agreements.refused.down_below_net"), simulate_agreement(@customer, [ @nf1, @nf2 ], down: 154_366).error
    late = simulate_agreement(@customer, [ @nf1, @nf2 ], down_on: Date.new(2026, 11, 20))
    assert_equal I18n.t("agreements.refused.down_due_range", from: "03/11/2026", to: "09/11/2026"), late.error
    assert_equal I18n.t("agreements.refused.down_due_range", from: "03/11/2026", to: "09/11/2026"), simulate_agreement(@customer, [ @nf1, @nf2 ], down_on: Date.new(2026, 10, 30)).error
  end

  test "R213: a entrada em dia não útil passa ao dia útil seguinte" do
    quote = simulate_agreement(@customer, [ @nf1, @nf2 ], down_on: Date.new(2026, 11, 7))

    assert_equal Date.new(2026, 11, 9), quote.down_payment_on
    assert_nil quote.error
  end

  test "R215: à vista, a entrada é o valor líquido do acordo, com o teto do à vista (30% na correção)" do
    quote = simulate_agreement(@customer, [ @nf1, @nf2 ], mode: "cash", discounts: { "fine" => 5_000, "correction" => 3_000 }, down: nil, installments: nil, day: nil)

    assert_nil quote.error
    assert_equal quote.net_cents, quote.down_payment_cents
    assert_equal 1, quote.schedule.size
    assert_equal "cash", quote.mode
    assert_nil simulate_agreement(@customer, [ @nf1, @nf2 ], mode: "cash", discounts: { "correction" => 3_100 }, down: nil, installments: nil).error
  end

  test "R215: todos os componentes com 100% de desconto é perdão total" do
    @alfa.setting.update!(installment_method: "none")
    Tier.catch_all_of(@alfa).update!(agreement_caps: { "installment" => Agreements::Caps::COMPONENTS.to_h { |c| [ c, 100 ] }, "cash" => {} })
    forgiveness = Agreements::Caps::COMPONENTS.to_h { |c| [ c, 10_000 ] }
    quote = simulate_agreement(@customer, [ @nf1, @nf2 ], discounts: forgiveness)

    assert_equal I18n.t("agreements.refused.total_forgiveness"), quote.error
  end

  test "R215, W3: a entrada e as parcelas precisam ser maiores que o mínimo para quebrar" do
    @alfa.setting.update!(agreement_policies: { "minimum_to_break" => { "kind" => "cents", "value" => 31_133 } })
    quote = simulate_agreement(@customer, [ @nf1, @nf2 ])

    assert_equal I18n.t("agreements.refused.minimum_to_break", min: "311,33"), quote.error
    @alfa.setting.update!(agreement_policies: { "minimum_to_break" => { "kind" => "cents", "value" => 31_132 } })
    assert_nil simulate_agreement(@customer, [ @nf1, @nf2 ]).error
  end

  test "R211: título que não está em cobrança, de outro cliente ou sem escolha é recusado" do
    assert_equal I18n.t("agreements.refused.bills_required"), refuse_agreement { simulate_agreement(@customer, []) }
    @nf1.update!(status: "withdrawn")
    assert_equal I18n.t("agreements.refused.bill_not_open", number: "NF-1"), refuse_agreement { simulate_agreement(@customer, [ @nf1 ]) }
    other = make_bill(@alfa, number: "NF-9", amount_cents: 10_000, document: PaymentsHelper::JOAO, contract_code: "CT-9", due: ChargesTestHelper::DUE, name: "João")
    assert_equal I18n.t("agreements.refused.bill_unknown"), refuse_agreement { simulate_agreement(@customer, [ other ]) }
  end

  test "revisão 12: a faixa da entrada, as parcelas que a R215 aceita e os tetos dos descontos" do
    limits = simulate_agreement(@customer, [ @nf1, @nf2 ]).limits

    assert_equal 15_437, limits.down_min # 10% de R$ 1.543,66, para cima
    assert_equal 144_366, limits.down_max # o valor líquido menos a parcela mínima de R$ 100,00
    assert_equal (1..12).to_a, limits.installment_counts
    assert_equal 50, limits.profile_discounts["fine"]
    assert_equal 0, limits.profile_discounts["principal"]
    assert_equal [ 1, 2 ], simulate_agreement(@customer, [ @nf1, @nf2 ], down: 134_366).limits.installment_counts # sobram R$ 200,00: três parcelas ficariam abaixo da mínima
    assert_equal [ 1 ], simulate_agreement(@customer, [ @nf1, @nf2 ], down: 150_000).limits.installment_counts
  end

  test "revisão 12: sem a pessoa mexer, a entrada é a maior entre o mínimo do item e o do perfil" do
    tier = Tier.catch_all_of(@alfa)
    profile = memberships(:carlos_alfa).profile
    AgreementLimit.for(profile, tier).update!(min_down_payment_pct: 30)
    input = agreement_input([ @nf1, @nf2 ], down: nil).with(auto_down: true)
    quote = Agreements::Simulation.new(user: users(:carlos), customer: @customer, input: input).call

    assert_equal (154_366 * 30 + 99) / 100, quote.down_payment_cents
    assert_equal 15_437, quote.limits.down_min
    assert_equal quote.down_payment_cents, quote.limits.down_initial
  end

  test "R211: o limite de 100 títulos" do
    ids = (1..101).to_a
    input = Agreements::Simulation::Input.new(bill_ids: ids, mode: "installments", discounts_bp: {}, down_payment_cents: nil, down_payment_on: nil, installments: 2, day: 5, replace: false)

    assert_equal I18n.t("agreements.refused.bills_limit", max: 100), refuse_agreement { Agreements::Simulation.new(user: users(:carlos), customer: @customer, input: input).call }
  end

  test "R249: a cidade que não casa com o IBGE avisa na simulação, sem impedir" do
    quote = simulate_agreement(@customer, [ @nf1, @nf2 ])

    assert_includes quote.warnings, I18n.t("agreements.warnings.city_unrecognized")
    assert_nil quote.error
  end

  test "N23: o teto em reais do valor líquido do perfil leva a proposta à aprovação" do
    limit = AgreementLimit.for(profiles(:alfa_operator), Tier.catch_all_of(@alfa))
    limit.update!(ceiling_value_cents: 100_000)

    assert_equal "pending", simulate_agreement(@customer, [ @nf1, @nf2 ]).status
  end

  test "DA30: os honorários são recalculados sobre o negociado e depois recebem o desconto" do
    Tier.catch_all_of(@alfa).update!(fees_pct: 10, fees_in_contract: true)
    recalc_values(@alfa, today: AGREEMENT_DAY)
    plain = simulate_agreement(@customer, [ @nf1, @nf2 ], discounts: { "fine" => 5_000, "interest" => 5_000 }).rows.first
    base_fees = plain.base["fees"]
    after = plain.after
    expected = Charges::Calculator.round_cents((after["principal"] + after["correction"] + after["fine"] + after["interest"]) * 0.10)

    assert_operator base_fees, :>, 0
    assert_equal expected, after["fees"]

    @alfa.setting.update!(agreement_policies: { "fees" => "on_base" })
    on_base = simulate_agreement(@customer, [ @nf1, @nf2 ], discounts: { "fine" => 5_000, "interest" => 5_000 }).rows.first
    assert_equal base_fees, on_base.after["fees"]
  end
end
