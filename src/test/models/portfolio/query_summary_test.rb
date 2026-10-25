require "test_helper"

class Portfolio::QuerySummaryTest < ActiveSupport::TestCase
  REFERENCE = Date.new(2026, 10, 18)

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    @beta.setting.update!(aging_brackets: [ { from: 1, to: 60 }, { from: 61, to: nil } ])
    @maria = customer(@alfa, "529.982.247-25", "Maria da Silva")
    @jose = customer(@alfa, "390.533.447-05", "José Conceição")
    @sem_titulos = customer(@alfa, "111.444.777-35", "Ana Souza")
    @joao_beta = customer(@beta, "529.982.247-25", "Maria Beta")
    bill(@maria, "NF-1", Date.new(2026, 9, 10), 100_000)      # 38 dias de atraso
    bill(@maria, "NF-2", Date.new(2026, 7, 15), 50_000)       # 95 dias
    bill(@maria, "NF-3", Date.new(2026, 12, 10), 20_000)      # a vencer
    bill(@jose, "NF-4", Date.new(2026, 12, 10), 80_000)       # só a vencer
    bill(@joao_beta, "NF-5", Date.new(2026, 9, 10), 70_000)   # 38 dias, faixa 1–60 da Beta
  end

  def customer(tenant, document, name) = Customer.create!(tenant: tenant, document: Document.normalize(document), name: name)

  def bill(customer, number, due, cents)
    contract = Contract.find_or_create_by!(tenant: customer.tenant, code: "C-#{customer.id}")
    Bill.create!(tenant: customer.tenant, customer: customer, contract: contract, number: number, due_date: due, amount_cents: cents)
  end

  def query(user) = Portfolio::Query.new(user, reference: REFERENCE)

  test "a lista traz vencido, a vencer, maior atraso e faixa (R17, R19, R21)" do
    rows = query(users(:joana)).customers.index_by(&:name)

    maria = rows.fetch("Maria da Silva")
    assert_equal [ 3, 150_000, 20_000, 95 ], [ maria.bills_count, maria.overdue_cents, maria.upcoming_cents, maria.max_days_overdue ]
    assert_equal "91–180", query(users(:joana)).bracket_label(@alfa.id, maria.max_days_overdue)
    assert_equal "sem atraso", query(users(:joana)).bracket_label(@alfa.id, rows.fetch("José Conceição").max_days_overdue)
  end

  test "sem busca, não lista quem não tem título em cobrança; com busca, lista qualquer cliente do credor (R21)" do
    assert_not_includes query(users(:joana)).customers.map(&:name), "Ana Souza"
    assert_equal [ "Ana Souza" ], query(users(:joana)).customers(search: "ana sou").map(&:name)
  end

  test "a busca ignora acento e maiúsculas e acha por parte do documento" do
    assert_equal [ "José Conceição" ], query(users(:joana)).customers(search: "JOSE conceicao").map(&:name)
    assert_equal [ "Maria da Silva" ], query(users(:joana)).customers(search: "529.982").map(&:name)
  end

  test "o filtro de faixa usa as faixas do credor de cada cliente (MT-7)" do
    ana = query(users(:ana))
    por_faixa = ana.customers(bracket: 1).map(&:name)

    assert_equal [ "Maria da Silva" ].sort, (ana.customers(bracket: 3).map(&:name)).sort
    assert_includes ana.customers(bracket: 0).map(&:name), "Maria Beta"
    assert_equal [ "José Conceição" ], ana.customers(bracket: -1).map(&:name)
    assert_not_includes por_faixa, "Maria Beta"
  end

  test "cada usuário vê só os credores em que tem a permissão de consultar (MT-5)" do
    assert_equal [ "José Conceição", "Maria da Silva" ], query(users(:joana)).customers.map(&:name).sort
    assert_equal [ "José Conceição", "Maria Beta", "Maria da Silva" ], query(users(:ana)).customers.map(&:name).sort
    assert_empty query(users(:sem_vinculo)).customers
  end

  test "no modo só na ficha, a lista traz só quem tem título vencido (R20)" do
    @alfa.setting.update!(upcoming_display: :detail_only)

    assert_equal [ "Maria da Silva" ], query(users(:joana)).customers.map(&:name)
  end

  test "ordenação por coluna e paginação de 20 por padrão" do
    por_nome = query(users(:joana)).customers(sort: "name", direction: "asc").map(&:name)
    assert_equal [ "José Conceição", "Maria da Silva" ], por_nome

    pagination = Pagination.new(query(users(:ana)).customers, page: 1, per_page: 20)
    assert_equal [ 20, 3, 1 ], [ pagination.per_page, pagination.total, pagination.pages ]
    assert_equal [ 20, 20 ], [ Pagination.new(Customer.all, page: 1, per_page: 33).per_page, Pagination.new(Customer.all, page: 0, per_page: nil).per_page ]
  end

  test "o resumo de um credor conta cada título uma vez e distribui por faixa (R23)" do
    summary = Portfolio::Summary.new(users(:ana), reference: REFERENCE)
    alfa = summary.for_tenant(@alfa)
    beta = summary.for_tenant(@beta)

    assert_equal [ 2, 4, 150_000, 100_000, 1 ], [ alfa[:customers], alfa[:bills], alfa[:overdue_cents], alfa[:upcoming_cents], alfa[:customers_overdue] ]
    assert_equal [ 0, 1, 0, 1, 0, 0 ], alfa[:by_bill].map { |row| row[:count] }
    assert_equal [ 0, 0, 0, 1, 0, 0 ], alfa[:by_customer].map { |row| row[:count] }
    assert_equal 150_000, alfa[:by_customer][3][:cents]
    assert_equal [ "1–60", "mais de 60" ], beta[:labels]
    assert_equal [ 70_000, 0 ], beta[:by_bill].map { |row| row[:cents] }
  end

  test "o resumo soma os credores visíveis; com faixas diferentes traz os totais e não as tabelas por faixa (25/10/2026)" do
    total = Portfolio::Summary.new(users(:ana), reference: REFERENCE).totals

    assert_equal 2, total[:tenants]
    assert_equal [ 3, 5, 220_000, 100_000 ], [ total[:customers], total[:bills], total[:overdue_cents], total[:upcoming_cents] ]
    assert_equal false, total[:same_brackets]
    assert_nil total[:labels]
    assert_nil total[:by_bill]
    assert_nil total[:by_customer]
  end

  test "com as mesmas faixas nos credores, as tabelas por faixa somam os credores" do
    @beta.setting.update!(aging_brackets: @alfa.setting.aging_brackets)
    total = Portfolio::Summary.new(users(:ana), reference: REFERENCE).totals

    assert total[:same_brackets]
    assert_equal [ 0, 2, 0, 1, 0, 0 ], total[:by_bill].map { |row| row[:count] }
    assert_equal 170_000, total[:by_bill][1][:cents]
    assert_equal [ 0, 1, 0, 1, 0, 0 ], total[:by_customer].map { |row| row[:count] }
    assert_equal 220_000, total[:by_customer].sum { |row| row[:cents] }
  end

  test "o resumo só soma os credores em que o usuário consulta a carteira (V10) e quem tem um credor vê o dele" do
    only_alfa = Portfolio::Summary.new(users(:joana), reference: REFERENCE).totals
    assert_equal 1, only_alfa[:tenants]
    assert_equal [ 2, 4, 150_000 ], [ only_alfa[:customers], only_alfa[:bills], only_alfa[:overdue_cents] ]
    assert only_alfa[:same_brackets]
    assert_equal Portfolio::Summary.new(users(:joana), reference: REFERENCE).for_tenant(@alfa).except(:agreements), only_alfa.except(:agreements)
  end

  test "mudar as faixas vale na hora e fica registrado; só a configuração do credor muda (R18)" do
    service = Portfolio::SettingsService.new
    service.update_brackets(@alfa, [ { from: 1, to: 60 }, { from: 61, to: nil } ], users(:joana))

    assert_equal [ "1–60", "mais de 60" ], Portfolio::Summary.new(users(:joana), reference: REFERENCE).totals[:labels]
    change = Change.find_by!(subject_type: "settings", subject_id: @alfa.id, field: "aging_brackets")
    assert_equal users(:joana), change.user
    assert_includes change.before, "361"

    assert_raises(Portfolio::InvalidBrackets) { service.update_brackets(@alfa, [ { from: 5, to: nil } ], users(:joana)) }
    assert_equal 2, @alfa.reload.setting.aging_brackets.size

    service.update_upcoming_display(@alfa, "summed", users(:joana))
    assert @alfa.reload.setting.summed?
    assert Change.exists?(subject_id: @alfa.id, field: "upcoming_display", before: "separate", after: "summed")
  end
end
