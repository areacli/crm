require "application_system_test_case"

# Telas da carteira no navegador: cada uma passa no axe, e a busca da lista se refaz pelo htmx sem recarregar a página.
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
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
  end

  test "resumo, lista, ficha, envio, importação e configuração passam no axe" do
    assert_acessivel

    visit customers_path
    assert_selector "h1", text: "Clientes"
    assert_acessivel

    click_link "Maria Souza"
    assert_selector "h1", text: "Maria Souza"
    assert_acessivel

    visit new_import_path
    assert_acessivel

    visit import_path(@import)
    assert_selector "h1", text: "Importação de"
    assert_acessivel
    click_button "Confirmar"
    assert_selector "dialog[open]", text: "Confirmar a importação?"
    assert_acessivel
    within("dialog[open]") { click_button "Cancelar" }

    visit imports_path
    assert_acessivel

    visit settings_portfolio_path
    assert_acessivel
  end

  test "a busca refaz a lista sem recarregar a página" do
    visit customers_path
    assert_text "Maria Souza"
    assert_text "José Lima"
    page.execute_script("window.marcaDaPagina = 1")

    fill_in "Buscar por nome, documento ou contrato", with: "jose"

    assert_no_text "Maria Souza"
    assert_text "José Lima"
    assert_equal 1, page.evaluate_script("window.marcaDaPagina")
  end
end
