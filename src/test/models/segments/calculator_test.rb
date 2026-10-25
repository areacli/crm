require "test_helper"

# Critérios e cálculo do segmento do contrato (08, R148 a R153): um caso por critério e por exemplo da especificação.
class SegmentsCalculatorTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
  end

  test "R149 e critério de aceite: o primeiro segmento que casa vale; PF recente, PF e Demais" do
    make_segment(@alfa, "Varejo PF recente", person_type: "person", min_overdue_days: 1, max_overdue_days: 90, max_balance_cents: 500_000)
    make_segment(@alfa, "PF", person_type: "person")
    maria = make_contract(@alfa, "C-MARIA", bills: [ { overdue: 40, cents: 120_000 } ], customers: [ customer_of(@alfa, FakeData.cpf(1)) ])
    jose = make_contract(@alfa, "C-JOSE", bills: [ { overdue: 200, cents: 90_000 } ], customers: [ customer_of(@alfa, FakeData.cpf(2)) ])
    loja = make_contract(@alfa, "C-LOJA", bills: [ { overdue: 10, cents: 30_000 } ], customers: [ customer_of(@alfa, CNPJ_A) ])
    recalc(@alfa)

    assert_equal [ "Varejo PF recente", "PF", "Demais" ], [ segment_of(maria), segment_of(jose), segment_of(loja) ]
  end

  test "R150: produto pela política, três opções (título mais atrasado, maior saldo, qualquer título)" do
    make_segment(@alfa, "Cartões", products: [ "Cartão" ])
    make_segment(@alfa, "Empréstimos", products: [ "emprestimo" ])
    jose = make_contract(@alfa, "C-JOSE", bills: [ { overdue: 200, cents: 500_000, product: "Empréstimo" }, { overdue: 30, cents: 30_000, product: "cartao" } ])
    recalc(@alfa)
    assert_equal "Empréstimos", segment_of(jose)

    @alfa.setting.update!(segment_product_policy: "largest_balance")
    recalc(@alfa)
    assert_equal "Empréstimos", segment_of(jose)

    @alfa.setting.update!(segment_product_policy: "any_bill")
    recalc(@alfa)
    assert_equal "Cartões", segment_of(jose)
  end

  test "R150 revisão 1: pelo título mais atrasado, título sem produto é pulado; sem acento e sem maiúsculas" do
    make_segment(@alfa, "Cartões", products: [ "Cartão de crédito" ])
    contract = make_contract(@alfa, "C-1", bills: [ { overdue: 300, cents: 10_000 }, { overdue: 20, cents: 10_000, product: "  CARTAO   de crédito " } ])
    recalc(@alfa)
    assert_equal "Cartões", segment_of(contract)
  end

  test "R150: quantidade de títulos vencidos, de 3 a 10; vazio aceita qualquer" do
    make_segment(@alfa, "Muitos vencidos", min_overdue_bills: 3, max_overdue_bills: 10)
    four = make_contract(@alfa, "C-4", bills: [ { overdue: 5 }, { overdue: 6 }, { overdue: 7 }, { overdue: 8 }, { overdue: -20 } ])
    two = make_contract(@alfa, "C-2", bills: [ { overdue: 5 }, { overdue: 6 }, { overdue: -20 } ])
    recalc(@alfa)
    assert_equal [ "Muitos vencidos", "Demais" ], [ segment_of(four), segment_of(two) ]
  end

  test "R150: percentual do valor vencido, de 80% a 100%, cerca de 84% casa e 50% não" do
    make_segment(@alfa, "Quase todo vencido", min_overdue_percent: 80, max_overdue_percent: 100)
    most = make_contract(@alfa, "C-84", bills: [ { overdue: 10, cents: 530_000 }, { overdue: -5, cents: 100_000 } ])
    half = make_contract(@alfa, "C-50", bills: [ { overdue: 10, cents: 100_000 }, { overdue: -5, cents: 100_000 } ])
    recalc(@alfa)
    assert_equal [ "Quase todo vencido", "Demais" ], [ segment_of(most), segment_of(half) ]
  end

  test "R150 e R19a: com 'só na ficha' só os títulos vencidos contam, o percentual é 100% e o contrato só a vencer fica sem segmento" do
    @alfa.setting.update!(upcoming_display: "detail_only")
    make_segment(@alfa, "Quase todo vencido", min_overdue_percent: 100)
    mixed = make_contract(@alfa, "C-M", bills: [ { overdue: 10, cents: 530_000 }, { overdue: -5, cents: 100_000 } ])
    only_upcoming = make_contract(@alfa, "C-U", bills: [ { overdue: -5, cents: 100_000 } ])
    recalc(@alfa)
    assert_equal "Quase todo vencido", segment_of(mixed)
    assert_nil only_upcoming.reload.segment_id
  end

  test "R150: número de clientes, de 2 a 3" do
    make_segment(@alfa, "Famílias", min_customers: 2, max_customers: 3)
    one = make_contract(@alfa, "A", bills: [ {} ], customers: [ customer_of(@alfa, FakeData.cpf(11)) ])
    two = make_contract(@alfa, "B", bills: [ {} ], customers: [ customer_of(@alfa, FakeData.cpf(12)), customer_of(@alfa, FakeData.cpf(13)) ])
    three = make_contract(@alfa, "C", bills: [ {} ], customers: [ customer_of(@alfa, FakeData.cpf(14)), customer_of(@alfa, FakeData.cpf(15)), customer_of(@alfa, FakeData.cpf(16)) ])
    recalc(@alfa)
    assert_equal [ "Demais", "Famílias", "Famílias" ], [ segment_of(one), segment_of(two), segment_of(three) ]
  end

  test "R150 e R153: idade do contrato; 11 dias depois deixa de casar e a mudança entra no histórico com a data" do
    make_segment(@alfa, "Recentes", min_age_days: 0, max_age_days: 30)
    young = make_contract(@alfa, "D", bills: [ {} ], created_ago: 20)
    old = make_contract(@alfa, "E", bills: [ {} ], created_ago: 200)
    recalc(@alfa)
    assert_equal [ "Recentes", "Demais" ], [ segment_of(young), segment_of(old) ]

    travel_to 11.days.from_now do
      recalc(@alfa)
      assert_equal "Demais", segment_of(young)
      assert_equal [ [ "Recentes", Date.current - 11 ], [ "Demais", Date.current ] ], young.contract_segments.order(:since).map { |h| [ h.segment.name, h.since ] }
    end
  end

  test "R150 e MT-16: tipo pelos responsáveis financeiros; misto só casa com Misto e tanto faz; sem declarado vale o dos titulares" do
    make_segment(@alfa, "PF", person_type: "person")
    make_segment(@alfa, "PJ", person_type: "company")
    make_segment(@alfa, "Mistos", person_type: "mixed")
    ana = customer_of(@alfa, FakeData.cpf(31))
    loja = customer_of(@alfa, CNPJ_A)
    mixed = make_contract(@alfa, "M", bills: [ {} ], customers: [ ana, loja ], roles: { ana.id => %w[holder financial_responsible], loja.id => %w[financial_responsible] })
    holders = make_contract(@alfa, "H", bills: [ {} ], customers: [ customer_of(@alfa, FakeData.cpf(32)) ], roles: {})
    only_holders = make_contract(@alfa, "S", bills: [ {} ], customers: [ customer_of(@alfa, FakeData.cpf(33)), customer_of(@alfa, CNPJ_B) ],
                                 roles: { Customer.find_by(document: FakeData.cpf(33)).id => %w[holder], Customer.find_by(document: CNPJ_B).id => %w[holder] })
    recalc(@alfa)
    assert_equal [ "Mistos", "PF", "Mistos" ], [ segment_of(mixed), segment_of(holders), segment_of(only_holders) ]

    # Um segmento que exige PF não pega o misto, e a conferência (R154) conta os mistos que mudam.
    @alfa.segments.where(name: "Mistos").update_all(active: false)
    recalc(@alfa)
    assert_equal "Demais", segment_of(mixed)
  end

  test "R148: já quebrou acordo é marca histórica do contrato" do
    make_segment(@alfa, "Quebrou", broke_agreement: "yes")
    broke = make_contract(@alfa, "F", bills: [ {} ])
    broke.update!(broke_agreement: true)
    clean = make_contract(@alfa, "G", bills: [ {} ])
    recalc(@alfa)
    assert_equal [ "Quebrou", "Demais" ], [ segment_of(broke), segment_of(clean) ]
  end

  test "R152: contrato sem título em cobrança fica sem segmento e recebe de novo quando volta" do
    contract = make_contract(@alfa, "P", bills: [ { cents: 50_000 } ])
    recalc(@alfa)
    assert_equal "Demais", segment_of(contract)
    contract.bills.update_all(status: "paid")
    travel_to(1.day.from_now) { recalc(@alfa) }
    assert_nil contract.reload.segment_id
    assert_equal [ "Demais", nil ], contract.contract_segments.order(:since).map { |h| h.segment&.name }
    contract.bills.update_all(status: "active")
    travel_to(2.days.from_now) { recalc(@alfa) }
    assert_equal "Demais", segment_of(contract)
  end

  test "R152 e MT-9: o mesmo CPF em dois credores tem contratos e segmentos independentes" do
    make_segment(@alfa, "Curto", max_overdue_days: 60)
    make_segment(@beta, "Longo", min_overdue_days: 100)
    alfa = make_contract(@alfa, "X", bills: [ { overdue: 40 } ], customers: [ customer_of(@alfa, FakeData.cpf(41)) ])
    beta = make_contract(@beta, "X", bills: [ { overdue: 200 } ], customers: [ customer_of(@beta, FakeData.cpf(41)) ])
    recalc(@alfa)
    assert_nil beta.reload.segment_id, "a Beta não é recalculada pela Alfa"
    recalc(@beta)
    assert_equal [ "Curto", "Longo" ], [ segment_of(alfa), segment_of(beta) ]
  end

  test "R149: segmento desativado não casa; credor sem segmento criado fica todo no Demais" do
    inactive = make_segment(@alfa, "Antigo", min_overdue_days: 1)
    inactive.update!(active: false)
    contract = make_contract(@alfa, "Z", bills: [ { overdue: 5 } ])
    recalc(@alfa)
    assert_equal "Demais", segment_of(contract)
  end

  test "duas mudanças no mesmo dia regravam a linha do dia" do
    first = make_segment(@alfa, "Um", min_overdue_days: 1)
    contract = make_contract(@alfa, "W", bills: [ { overdue: 5 } ])
    recalc(@alfa)
    first.update!(active: false)
    recalc(@alfa)
    assert_equal [ "Demais" ], contract.contract_segments.map { |h| h.segment.name }
  end
end
