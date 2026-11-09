require "application_system_test_case"

# Telas da carteira no navegador, nas abas da casca, e a busca da lista refaz a grade sem recarregar a página.
class PortfolioScreensSystemTest < ApplicationSystemTestCase
  setup do
    alfa = tenants(:alfa)
    contract = Contract.create!(tenant: alfa, code: "C-1")
    @maria = Customer.create!(tenant: alfa, document: "52998224725", name: "Maria Souza")
    @jose = Customer.create!(tenant: alfa, document: "39053344705", name: "José Lima")
    [ @maria, @jose ].each_with_index do |customer, index|
      Bill.create!(tenant: alfa, contract: contract, customer: customer, number: "T#{index}", due_date: Date.current - 40, amount_cents: 10_000)
    end
    @import = Import.create!(tenant: alfa, user: users(:joana), mode: :full_sync, status: :checked, original_name: "carteira.csv", size_bytes: 2048,
                             progress_percent: 100, checked_at: Time.current,
                             summary: { lines: 2, valid: 2, rejected: 0, customers: 2, customers_new: 0, amount_formatted: "200,00", bills_new: 0, bills_updated: 0,
                                        bills_unchanged: 2, to_withdraw: { count: 1, amount_cents: 5000 } })
    entrar_na_casca
  end

  test "resumo, lista, ficha, envio, importação e configuração abrem nas abas" do
    assert_selector ".aba-raiz h1", text: "Resumo da carteira", wait: 15

    # Clientes e a ficha estão na SPA (fase 3), onde o axe não roda (D7).
    visit customers_path
    assert_selector ".lista h1", text: "Clientes", wait: 15
    find(".lista .datagrid-row a", text: "Maria Souza").click
    assert_selector ".aba-raiz .cabecalho-da-pagina h1", text: "Maria Souza"

    # Importações estão na SPA (fase 5): a confirmação curta em diálogo preso à aba.
    visit new_import_path
    assert_selector ".aba-raiz .filebox", wait: 15

    visit import_path(@import)
    assert_selector ".aba-raiz h1", text: "Importação de", wait: 15
    within(".aba-raiz #importacao") { click_link "Confirmar" }
    assert_selector ".window .panel-title", text: "Confirmar a importação?"
    no_dialogo { click_button "Cancelar" }
    assert_no_selector ".dialogo-conteudo"

    visit settings_portfolio_path # o endereço antigo leva à aba na casca
    assert_selector ".aba-raiz h1", text: "Carteira", wait: 15
  end

  test "a busca refaz a grade sem recarregar a página" do
    visit customers_path
    assert_selector ".lista .datagrid-row", text: "Maria Souza", wait: 15
    assert_selector ".lista .datagrid-row", text: "José Lima"
    page.execute_script("window.marcaDaPagina = 1")

    within(".lista") { fill_in "Buscar", with: "jose" }

    assert_no_selector ".lista .datagrid-row", text: "Maria Souza"
    assert_selector ".lista .datagrid-row", text: "José Lima"
    assert_equal 1, page.evaluate_script("window.marcaDaPagina")
  end
end
