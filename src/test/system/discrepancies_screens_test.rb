require "application_system_test_case"

# Carteira revista no navegador (05): lista e detalhe das divergências, histórico do título, ficha com excedente, conferência e política, no axe.
class DiscrepanciesScreensSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @bill = paid_bill
    run_portfolio_import([ bill_line("NF-1024/3", "300,00") ], confirm: true)
    @discrepancy = ValueDiscrepancy.sole
    paid_bill(number: "NF-C", document: JOAO, contract_code: "CT-C", name: "João C")
    @checked = run_portfolio_import([ bill_line("NF-C", "300,00", "documento" => JOAO, "nome" => "João C", "contrato" => "CT-C") ])
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
  end

  test "lista, detalhe, histórico, ficha, conferência e política passam no axe e não rolam na horizontal" do
    click_link "Divergências de valor (1)"
    assert_selector "h1", text: "Divergências de valor"
    assert_selector "th a", text: "NF-1024/3"
    assert_acessivel
    assert_no_horizontal_scroll

    click_link "NF-1024/3"
    assert_selector "h1", text: "Divergência do título NF-1024/3"
    assert_acessivel
    click_link "Ver o histórico do título"
    assert_selector "h2", text: "Linha do tempo"
    assert_acessivel

    visit customer_path(@bill.customer)
    assert_selector "h2", text: "Crédito por contrato"
    assert_acessivel
    assert_no_horizontal_scroll

    visit import_path(@checked)
    assert_selector "h2", text: "Divergências de valor: 1 título"
    assert_acessivel

    visit settings_portfolio_path
    assert_text "Divergência de valor"
    assert_acessivel
  end

  test "trata a divergência pela tela, com nota" do
    visit value_discrepancy_path(@discrepancy)
    click_button "Tratar divergência"
    fill_in "Nota", with: "credor confirmou o desconto"
    click_button "Tratar divergência"
    assert_text "Divergência tratada."
    assert_acessivel
    assert_predicate @discrepancy.reload, :handled?
  end

  def assert_no_horizontal_scroll
    assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth"), "rolagem horizontal em #{page.current_path}"
  end
end
