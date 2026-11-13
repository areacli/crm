require "test_helper"

# A grade que troca de página não pede o total de novo; quem busca conta sempre, porque o total vai para a trilha da operação (14, R320).
class CustomerListTotalTest < ActionDispatch::IntegrationTest
  setup do
    make_contract(tenants(:alfa), "CT-1", customers: [ customer_of(tenants(:alfa), FakeData.cpf(9101), "Maria Total") ], bills: [ { overdue: 10 } ])
    sign_in_as users(:joana)
  end

  test "com sem_total a resposta vem sem o total; sem ele, com o total" do
    lista = get_clientes
    assert_equal 1, lista["rows"].size
    assert_equal 1, lista["total"]

    sem = get_clientes(sem_total: 1)
    assert_equal 1, sem["rows"].size
    assert_not sem.key?("total")
  end

  test "na busca, o total vem mesmo com sem_total" do
    assert_equal 1, get_clientes(busca: "maria total", sem_total: 1)["total"]
  end
end
