require "test_helper"

# Cartão Contratos acima das abas, filtro da ficha (padrões de interface, revisão 28): com mais de 5 contratos, os 5 primeiros e o escolhido, e o link para todos.
class CustomerContractsCardTest < ActionDispatch::IntegrationTest
  setup do
    @alfa = tenants(:alfa)
    @maria = customer_of(@alfa, FakeData.cpf(811), "Maria Sete Contratos")
    @contracts = (1..7).map { |index| make_contract(@alfa, "CT-#{index}", customers: [ @maria ], bills: [ { overdue: 10 } ]) }
    sign_in_as users(:joana)
  end

  test "mostra 5 contratos e o link para os 7; o escolhido aparece mesmo depois do quinto e passa de aba a aba" do
    get customer_url(@maria)
    assert_select "#contratos tbody tr:not(.detalhe-da-linha)", 5
    assert_select "#contratos p.mais a", text: "Mostrar os 7 contratos"
    assert_select "#contratos + nav.abas"

    get customer_url(@maria, contrato: @contracts.last.id, aba: "acionamentos")
    assert_select "#contratos tbody tr:not(.detalhe-da-linha)", 6
    assert_select "#contratos tr[data-atual] a[aria-current=true]", text: "CT-7"
    assert_select "#contratos a", text: "Ver todos os contratos"
    assert_select "#contratos a[aria-label='Filtrar a ficha pelo contrato CT-1'][href*='aba=acionamentos']"

    get customer_url(@maria, contratos: "todos")
    assert_select "#contratos tbody tr:not(.detalhe-da-linha)", 7
    assert_select "#contratos p.mais", 0
  end
end
