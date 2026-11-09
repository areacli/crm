require "test_helper"

# Endereços em português (padrões de interface, revisão 39): parâmetro e valor de filtro saem e são lidos em português, e o nome em inglês não vale.
class UrlEmPortuguesTest < ActionDispatch::IntegrationTest
  test "o tipo da importação vai e volta em português, e o nome em inglês não vale" do
    sign_in_as users(:joana)
    get new_import_url(tipo: "pagamentos"), headers: TRECHO
    assert_select "h1", text: "Importar pagamentos"
    get new_import_url(kind: "payments"), headers: TRECHO
    assert_select "h1", text: "Importar carteira"
  end

  test "os links e os filtros das telas saem em português" do
    sign_in_as users(:joana)
    get imports_url, headers: TRECHO
    assert_select "a[href='#{new_import_path}?tipo=pagamentos']"
    assert_select "a[href*='kind=']", 0
    get value_discrepancies_url, headers: TRECHO
    assert_select "select[name=situacao] option[selected][value=aberta]"
    assert_select "select[name=status]", 0
  end

  test "a lista de clientes lê a página e a busca em português" do
    sign_in_as users(:joana)
    get customers_url(format: :json), params: { pagina: 1, por_pagina: 10, busca: "inexistente" }, headers: TRECHO
    assert_response :success
    assert_equal 0, response.parsed_body["total"]
  end
end
