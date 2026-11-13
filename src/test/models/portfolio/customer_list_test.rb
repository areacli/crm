require "test_helper"

# A lista de clientes por caminhos curtos (plano técnico da lista com 200 mil): a página com o corte e o total sem agregar devolvem o mesmo que a consulta inteira.
class Portfolio::CustomerListTest < ActiveSupport::TestCase
  REFERENCE = Date.new(2026, 10, 18)

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    # Vencido com empates (cada valor em três clientes) e clientes só com título a vencer, sem atraso.
    (1..21).each do |i|
      person = customer(@alfa, i, format("Cliente %02d", 22 - i))
      bill(person, "A-#{i}", REFERENCE - (i % 3 + 1) * 40, (i % 7 + 1) * 1000)
      bill(person, "B-#{i}", REFERENCE + 30, i * 100)
    end
    (22..25).each { |i| bill(customer(@alfa, i, format("Cliente %02d", i)), "C-#{i}", REFERENCE + 10, i * 100) }
    bill(customer(@beta, 30, "Cliente da Beta"), "D-1", REFERENCE - 50, 9000)
    customer(@alfa, 31, "Sem Título")
  end

  def customer(tenant, seed, name) = Customer.create!(tenant: tenant, document: FakeData.cpf(9000 + seed), name: name)

  def bill(person, number, due, cents)
    contract = Contract.find_or_create_by!(tenant: person.tenant, code: "C-#{person.id}")
    Bill.create!(tenant: person.tenant, customer: person, contract: contract, number: number, due_date: due, amount_cents: cents)
  end

  def query(user = users(:ana)) = Portfolio::Query.new(user, reference: REFERENCE)

  # Página a página, com o corte, o resultado tem de ser a consulta inteira, na mesma ordem.
  def assert_same_as_full_list(**filters)
    full = query.customers(**filters).map(&:id)
    list = query.customer_list(**filters)
    per_page = 10
    paged = (1..(full.size / per_page + 2)).flat_map { |page| Portfolio::CustomerPagination.new(list, page: page, per_page: per_page).records.map(&:id) }

    assert_equal full, paged, "página a página, com #{filters}"
    assert_equal full.size, list.total, "total, com #{filters}"
  end

  test "a página com o corte é a da lista inteira em toda ordem, com empates e clientes sem atraso (R21)" do
    Portfolio::Query::SORTS.product(%w[asc desc]).each { |sort, direction| assert_same_as_full_list(sort: sort, direction: direction) }
  end

  test "o total e as páginas valem também com filtros" do
    assert_same_as_full_list(search: "cliente 0")
    assert_same_as_full_list(search: "sem título")
    assert_same_as_full_list(bracket: 0)
    assert_same_as_full_list(bracket: -1)
    assert_same_as_full_list(search: "cliente", bracket: -1)
    assert_same_as_full_list(tenant_id: @beta.id)
    assert_same_as_full_list(promise: "none", sort: "bills_count", direction: "asc")
    assert_same_as_full_list(promise: "open")
  end

  test "no modo só na ficha, total e páginas ficam com quem tem título vencido (R20)" do
    @alfa.setting.update!(upcoming_display: :detail_only)

    assert_same_as_full_list
    assert_same_as_full_list(sort: "max_days_overdue", direction: "asc")
    assert_equal 22, query.customer_list.total
  end

  test "a busca acha quem não tem título; sem busca, não entra" do
    assert_equal 0, query.customer_list.relation.where(name: "Sem Título").to_a.size
    assert_equal [ "Sem Título" ], query.customers(search: "sem titulo").map(&:name)
    assert_equal 1, query.customer_list(search: "sem titulo").total
  end

  test "o segmento inexistente não traz ninguém e não contraria o total" do
    list = query.customer_list(segment: 0)

    assert_empty list.relation
    assert_equal 0, list.total
  end
end
