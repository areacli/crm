require "test_helper"

# Motor de encargos (09, R164 a R172, R180, R181), sem banco, com os exemplos da especificação ao centavo e os índices reais de 2026
# (nenhum teste chama o Banco Central).
class ChargesCalculatorTest < ActiveSupport::TestCase
  IPCA = { Date.new(2026, 7, 1) => 0.07, Date.new(2026, 8, 1) => -0.32, Date.new(2026, 9, 1) => 0.82 }.freeze
  LEGAL = { Date.new(2026, 7, 1) => 0.706607, Date.new(2026, 8, 1) => 1.154527, Date.new(2026, 9, 1) => 1.499119, Date.new(2026, 10, 1) => 0.379020 }.freeze
  TODAY = Date.new(2026, 10, 21)
  DUE = Date.new(2026, 7, 15)

  def rule(**changes)
    Charges::Rule.new("Varejo PF recente", 0.02, "fixed", 0.01, "simple", "ipca", 0.0, "calendar", "corrected").with(**changes)
  end

  def tables(today: TODAY, policies: Charges::Policies.default, rates: { "ipca" => IPCA, "legal" => LEGAL })
    Charges::Tables.new(rates, today, policies)
  end

  def calc(rule, today: TODAY, policies: Charges::Policies.default, rates: { "ipca" => IPCA, "legal" => LEGAL }, amount: 100_000, due: DUE, **options)
    Charges::Calculator.call(tables(today: today, policies: policies, rates: rates), { 1 => rule }, amount, due, segment_today: 1, **options)
  end

  test "R164 a R169 e critério de aceite: Maria, R$ 1.000,00 vencido em 15/07/2026, calculado em 21/10/2026" do
    result = calc(rule)
    assert_equal [ 100_534, 2011, 3211, 0, 105_756 ], [ result.corrected_principal, result.fine, result.interest, result.fees, result.total ]
  end

  test "R166: juros compostos e taxa legal; com taxa legal a forma dos juros não se aplica" do
    assert_equal 3246, calc(rule(form: "compound")).interest
    assert_equal 3293, calc(rule(interest: "legal", rate: 0.0)).interest
    assert_equal 3293, calc(rule(interest: "legal", form: "compound")).interest
  end

  test "R165: 'último índice pro rata dia' estima outubro pelo IPCA de setembro, e a memória diz isso" do
    policies = Charges::Policies.new("last_prorated", "floor", "selic")
    result = calc(rule, policies: policies, memory: true)
    assert_equal 101_091, result.corrected_principal
    assert(result.stretches.flat_map { |stretch| stretch[:notes] }.any? { |note| note.include?("IPCA de 10/2026: estimado pelo de 09/2026") })
  end

  test "R165: só meses fechados deixa outubro de fora e a memória diz 'sem índice publicado'" do
    result = calc(rule, memory: true)
    assert(result.stretches.flat_map { |stretch| stretch[:notes] }.any? { |note| note.include?("IPCA de 10/2026: sem índice publicado") })
  end

  test "R167: multa de 2% sobre o principal corrigido; base de face (parâmetro do credor) usa o valor de face" do
    assert_equal 2011, calc(rule).fine
    assert_equal 2000, calc(rule(fine_base: "face")).fine
  end

  test "R168: honorários de 10% sobre principal corrigido, multa e juros" do
    assert_equal 10_576, calc(rule(fees: 0.10)).fees
  end

  test "R166 (parâmetro): convenção taxa ÷ 30 por dia corrido" do
    assert_equal round(100_534 * 0.01 / 30 * 98), calc(rule(convention: "thirty")).interest
  end

  test "R170/R226: pagamento parcial de R$ 400,00 em 15/09 cobre juros e multa antes do principal; depois, juros sobre o principal em aberto" do
    plain = rule(index: "")
    result = calc(plain, payments: [ [ Date.new(2026, 9, 15), 35_984 ] ]).minus_paid("interest" => 2016, "fine" => 2000)
    assert_equal [ 754, 0, 64_016, 64_770 ], [ result.interest, result.fine, result.corrected_principal, result.total ]
    on_payment = calc(plain, as_of: Date.new(2026, 9, 15))
    assert_equal [ 2016, 2000, 100_000 ], [ on_payment.interest, on_payment.fine, on_payment.principal ]
  end

  test "R226 (especificação 11): boleto de R$ 500,00 ao NF-2 em 30/10 cobre juros 7,37, multa 10,04, correção 2,05 e principal 480,54" do
    result = calc(rule, today: Date.new(2026, 10, 30), amount: 50_000, due: Date.new(2026, 9, 15))
    assert_equal [ 737, 1004, 205, 50_000, 51_946 ], [ result.interest, result.fine, result.correction, result.principal, result.total ]
  end

  test "R171: troca de segmento em 20/11 muda a taxa dos dias seguintes; dias anteriores ao histórico usam o primeiro segmento (DE4)" do
    a = rule(name: "Varejo PF recente", index: "")
    b = rule(name: "PF", index: "", rate: 0.02)
    periods = [ [ Date.new(2026, 10, 20), 1 ], [ Date.new(2026, 11, 20), 2 ] ]
    result = Charges::Calculator.call(tables(today: Date.new(2026, 11, 30)), { 1 => a, 2 => b }, 100_000, DUE, periods: periods, segment_today: 2, memory: true)
    months = 16.0 / 31 + 3 + 19.0 / 30
    assert_equal round(100_000 * (0.01 * months + 0.02 * 11.0 / 30)), result.interest
    assert_equal [ "Varejo PF recente", "PF" ], result.stretches.map { |stretch| stretch[:segment] }.uniq
    assert(result.notes.any? { |note| note.include?("antes disso vale o primeiro segmento registrado") })
  end

  test "R172: o cálculo parte do valor vigente do título" do
    assert_equal round(110_000 * 1.0053367858), calc(rule, amount: 110_000).corrected_principal
  end

  test "R164: título a vencer ou vencido hoje não tem encargos" do
    assert_equal 0, calc(rule, due: Date.new(2026, 11, 10)).total
    assert_equal [ 100_000, 0 ], calc(rule, due: TODAY).then { |r| [ r.principal, r.total ] }
  end

  test "caso de exceção: vencimento antes de janeiro de 2000 conta desde 01/01/2000 e a memória diz isso" do
    result = Charges::Calculator.call(tables, { 1 => rule(index: "", fine: 0.0) }, 100_000, Date.new(1998, 12, 10), segment_today: 1, memory: true)
    assert(result.notes.any? { |note| note.include?("antes de janeiro de 2000") })
    assert_equal Date.new(2000, 1, 1), result.stretches.first[:from]
    assert_equal round(100_000 * 0.01 * (26 * 12 + 9 + 21.0 / 31)), result.interest
  end

  test "R180: índice negativo, três opções, título de R$ 1.000,00 vencido em 31/07/2026 calculado em 05/09/2026 com IPCA de agosto -0,32%" do
    rates = { "ipca" => { Date.new(2026, 8, 1) => -0.32 } }
    { "floor" => 100_000, "always" => 99_680, "ignore" => 100_000 }.each do |option, cents|
      policies = Charges::Policies.new("closed_only", option, "selic")
      result = calc(rule(fine: 0.0, interest: "", rate: 0.0), today: Date.new(2026, 9, 5), policies: policies, rates: rates, due: Date.new(2026, 7, 31))
      assert_equal cents, result.corrected_principal, option
    end
  end

  test "R181: juros legais antes de 30/08/2024 em três opções, com os dois trechos na memória" do
    rates = { "selic" => { Date.new(2022, 3, 1) => 0.93 }, "ipca" => { Date.new(2022, 4, 1) => 1.06 } }
    legal = rule(interest: "legal", rate: 0.0, fine: 0.0)
    %w[selic one_percent none].each do |option|
      policies = Charges::Policies.new("closed_only", "floor", option)
      result = calc(legal, policies: policies, rates: rates, due: Date.new(2022, 3, 15), memory: true)
      before, after = result.stretches.first, result.stretches.second
      assert_equal [ Date.new(2024, 8, 29), Date.new(2024, 8, 30) ], [ before[:to], after[:from] ]
      case option
      when "selic"
        assert_equal 1.0, before[:factor]
        assert_includes before[:interest_origin], "Selic"
        assert_predicate before[:interest], :positive?
      when "one_percent"
        assert_operator before[:factor], :>, 1
        assert_includes before[:interest_origin], "1% ao mês"
      else
        assert_equal 0, before[:interest]
        assert_operator before[:factor], :>, 1
      end
    end
  end

  test "AN1: o encargo até o pagamento fica pela regra vigente nele, e a parte em aberto segue a regra nova dali em diante" do
    paid_on = Date.new(2026, 9, 15)
    old_rule = rule(index: "", fine: 0.0, rate: 0.01)
    new_rule = rule(index: "", fine: 0.0, rate: 0.02)
    versions = ->(_segment, _date) { old_rule }
    result = Charges::Calculator.call(tables, { 1 => new_rule }, 100_000, DUE, payments: [ [ paid_on, 35_984 ] ], segment_today: 1, versions: versions, consolidated: [ paid_on ])
    # Até 15/09, 1% sobre R$ 1.000,00 (R$ 20,1613); depois, 2% sobre R$ 640,16 (R$ 15,0747): R$ 35,24 no total, menos os R$ 20,16 pagos.
    assert_equal 3524, result.interest
    assert_equal 1508, result.minus_paid("interest" => 2016).interest
  end

  test "o caminho rápido (um trecho) dá o mesmo resultado do geral (forçado pela memória)" do
    random = Random.new(9)
    rates = { "ipca" => (1..9).to_h { |m| [ Date.new(2026, m, 1), random.rand(-0.5..1.2) ] }, "legal" => (1..10).to_h { |m| [ Date.new(2026, m, 1), 0.5 ] },
              "selic" => (1..12).to_h { |m| [ Date.new(2024, m, 1), 0.9 ] } }
    [ Charges::Policies.default, Charges::Policies.new("last_prorated", "always", "one_percent"), Charges::Policies.new("closed_only", "ignore", "none") ].each do |policies|
      tab = tables(policies: policies, rates: rates)
      200.times do
        the_rule = rule(fine: [ 0, 0.02 ].sample(random: random), interest: [ "", "fixed", "legal" ].sample(random: random), form: %w[simple compound].sample(random: random),
                        index: [ "", "ipca" ].sample(random: random), fees: [ 0, 0.1 ].sample(random: random))
        due = TODAY - random.rand(1..900)
        amount = random.rand(1000..10_000_000)
        fast = Charges::Calculator.call(tab, { 1 => the_rule }, amount, due, segment_today: 1)
        general = Charges::Calculator.call(tab, { 1 => the_rule }, amount, due, segment_today: 1, memory: true)
        assert_equal [ general.corrected_principal, general.fine, general.interest, general.fees ], [ fast.corrected_principal, fast.fine, fast.interest, fast.fees ], [ the_rule, due ].inspect
      end
    end
  end

  test "dia útil nacional: prorroga o vencimento no fim de semana, nos feriados e nos dias sem expediente bancário (M7)" do
    assert_equal Date.new(2026, 7, 15), Charges::BusinessDays.next_business(Date.new(2026, 7, 15))
    assert_equal Date.new(2026, 10, 19), Charges::BusinessDays.next_business(Date.new(2026, 10, 17))
    assert_equal Date.new(2026, 9, 8), Charges::BusinessDays.next_business(Date.new(2026, 9, 7))
    assert_equal Date.new(2026, 2, 18), Charges::BusinessDays.next_business(Date.new(2026, 2, 16))
    assert_equal Date.new(2026, 6, 5), Charges::BusinessDays.next_business(Date.new(2026, 6, 4))
  end

  private
    def round(value) = Charges::Calculator.round_cents(value)
end
