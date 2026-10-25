require "test_helper"

# Motor do título de acordo (11, R228): multa, juros de mora, correção e honorários só sobre o principal e a correção herdados, até a data do pagamento.
# Os números são os da especificação, ao centavo.
class Charges::AgreementCalculatorTest < ActiveSupport::TestCase
  RULE = Charges::AgreementRule.new(0.02, 0.01, "simple", "thirty", "corrected", "", 0.0)

  def calc(principal, correction, due, paid_on, rule: RULE, **options)
    Charges::AgreementCalculator.call(rule, principal: principal, correction: correction, due: due, paid_on: paid_on, **options)
  end

  test "R228: a parcela 2 de R$ 311,33 paga em 20/01 tem multa de R$ 5,95 e juros de 15 dias de R$ 1,49: R$ 318,77 no total" do
    result = calc(29_773, 0, Date.new(2027, 1, 5), Date.new(2027, 1, 20))

    assert_equal [ 595, 149, 0, 0 ], [ result.fine, result.interest, result.correction, result.fees ]
    assert_equal 1_360 + 29_773 + result.total, 31_877
    assert_equal({ "interest" => 149, "fine" => 595 }, result.components)
  end

  test "R234: a entrada atrasada quatro dias paga R$ 350,40 (multa de R$ 6,32 e juros de R$ 0,42 sobre principal e correção)" do
    result = calc(31_076, 534, Date.new(2026, 11, 5), Date.new(2026, 11, 9))

    assert_equal [ 632, 42 ], [ result.fine, result.interest ]
    assert_equal 35_040, 34_366 + result.total
  end

  test "R236: o título da quebra de 05/02 tem R$ 9,03 de encargos de atraso (multa R$ 5,95 e juros de 31 dias R$ 3,08) sobre a parcela 2" do
    result = calc(29_773, 0, Date.new(2027, 1, 5), Date.new(2027, 2, 5))

    assert_equal [ 595, 308, 903 ], [ result.fine, result.interest, result.total ]
  end

  test "AI3: o título da quebra e o de estorno não têm multa nova; os juros seguem" do
    result = calc(29_773, 0, Date.new(2027, 1, 5), Date.new(2027, 2, 5), fine: false)

    assert_equal [ 0, 308 ], [ result.fine, result.interest ]
  end

  test "R228: no dia do vencimento e antes dele não há encargo; título composto só de encargos herdados não tem base" do
    assert_equal Charges::AgreementCalculator::NONE, calc(29_773, 0, Date.new(2027, 1, 5), Date.new(2027, 1, 5))
    assert_equal Charges::AgreementCalculator::NONE, calc(29_773, 0, Date.new(2027, 1, 5), Date.new(2026, 12, 1))
    assert_equal Charges::AgreementCalculator::NONE, calc(0, 0, Date.new(2027, 1, 5), Date.new(2027, 2, 1))
  end

  test "R207a: a base da multa 'face' usa só o principal herdado, e a convenção 'calendar' conta a fração do mês do calendário" do
    face = Charges::AgreementRule.new(0.02, 0.0, "simple", "thirty", "face", "", 0.0)
    assert_equal 622, calc(31_076, 534, Date.new(2026, 11, 5), Date.new(2026, 11, 9), rule: face).fine

    tables = Charges::Tables.new({}, Date.new(2026, 12, 31), Charges::Policies.default)
    monthly = Charges::AgreementRule.new(0.0, 0.01, "simple", "calendar", "corrected", "", 0.0)
    # 1% ao mês pelo calendário: de 05/11 a 05/12 são 30/30 de novembro e 5/31 de dezembro.
    result = calc(10_000, 0, Date.new(2026, 11, 5), Date.new(2026, 12, 5), rule: monthly, tables: tables)
    assert_equal Charges::Calculator.round_cents(10_000 * 0.01 * (25.0 / 30 + 5.0 / 31)), result.interest
  end

  test "R228: a correção pelo índice congelado entre o vencimento e o pagamento, e os honorários sobre o corrigido, a multa e os juros" do
    tables = Charges::Tables.new({ "ipca" => { Date.new(2026, 11, 1) => 1.0, Date.new(2026, 12, 1) => 1.0 } }, Date.new(2027, 1, 31), Charges::Policies.default)
    rule = Charges::AgreementRule.new(0.0, 0.0, "simple", "thirty", "corrected", "ipca", 0.10)
    result = calc(10_000, 0, Date.new(2026, 11, 30), Date.new(2026, 12, 31), rule: rule, tables: tables)

    assert_equal 100, result.correction
    assert_equal Charges::Calculator.round_cents(10_100 * 0.10), result.fees
    assert_equal({ "fees" => 1_010, "correction" => 100 }, result.components)
  end

  test "R165: com a política 'índice negativo: o principal não cai', a deflação não reduz a base" do
    tables = Charges::Tables.new({ "ipca" => { Date.new(2026, 12, 1) => -1.0 } }, Date.new(2027, 1, 31), Charges::Policies.default)
    rule = Charges::AgreementRule.new(0.0, 0.01, "simple", "thirty", "corrected", "ipca", 0.0)
    result = calc(10_000, 0, Date.new(2026, 11, 30), Date.new(2026, 12, 31), rule: rule, tables: tables)

    assert_equal 0, result.correction
    assert_equal 103, result.interest
  end

  test "R228: juros compostos pela convenção ÷ 30 e regra sem encargos" do
    compound = Charges::AgreementRule.new(0.0, 0.03, "compound", "thirty", "corrected", "", 0.0)
    result = calc(10_000, 0, Date.new(2026, 11, 5), Date.new(2026, 11, 15), rule: compound)
    assert_equal Charges::Calculator.round_cents(10_000 * ((1 + 0.03 / 30)**10 - 1)), result.interest

    assert_equal Charges::AgreementCalculator::NONE, calc(10_000, 0, Date.new(2026, 11, 5), Date.new(2026, 11, 15), rule: Charges::AgreementRule.blank)
  end

  test "a regra se guarda e se lê do JSON congelado no acordo" do
    assert_equal RULE, Charges::AgreementRule.from_storage(JSON.parse(RULE.to_storage.to_json))
  end
end
