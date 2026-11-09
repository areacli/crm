require "application_system_test_case"

# Carteira revista no navegador (05), nas abas da casca: lista e detalhe das divergências, histórico do título, ficha com excedente, conferência e política.
class DiscrepanciesScreensSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @bill = paid_bill
    run_portfolio_import([ bill_line("NF-1024/3", "300,00") ], confirm: true)
    @discrepancy = ValueDiscrepancy.sole
    paid_bill(number: "NF-C", document: JOAO, contract_code: "CT-C", name: "João C")
    @checked = run_portfolio_import([ bill_line("NF-C", "300,00", "documento" => JOAO, "nome" => "João C", "contrato" => "CT-C") ])
    entrar_na_casca
  end

  test "lista, detalhe, histórico, ficha, conferência e política nas abas e janelas" do
    # A lista, a divergência (janela), o título (janela), a ficha e a importação estão na SPA (fases 3 e 5).
    visitar_lista value_discrepancies_path
    assert_selector "[id='resultado'] .datagrid-row a", text: "NF-1024/3"

    within("[id='resultado']") { click_link "NF-1024/3" }
    assert_selector ".window .panel-title", text: "Divergência do título NF-1024/3"
    within(".janela-corpo", match: :first) { click_link "Ver o histórico do título" }
    assert_selector ".janela-corpo h2", text: "Linha do tempo"

    visitar_ficha(@bill.customer, aba: "pagamentos")
    na_aba_interna { assert_selector "h2", text: "Crédito por contrato" }

    visit import_path(@checked)
    assert_selector ".aba-raiz h2", text: "Divergências de valor: 1 título", wait: 15

    # A carteira está na SPA (fase 7), fora do axe (D7).
    abrir_aba settings_portfolio_path
    assert_selector ".aba-raiz .politica .titulo", text: "Divergência de valor", wait: 10
  end

  test "trata a divergência pela tela, com nota" do
    # O endereço antigo da divergência leva à casca, que a abre em janela; o diálogo de tratar refaz a janela no fim.
    visit value_discrepancy_path(@discrepancy)
    assert_selector ".window .panel-title", text: /Divergência do título/, wait: 15
    within(".janela-corpo") { click_link "Tratar divergência" }
    no_dialogo { fill_in "Nota", with: "credor confirmou o desconto" }
    gravar_dialogo "Tratar divergência"
    assert_aviso "Divergência tratada."
    assert_no_selector ".janela-corpo a", text: "Tratar divergência", wait: 10
    assert_predicate @discrepancy.reload, :handled?
  end

  def assert_no_horizontal_scroll
    assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth"), "rolagem horizontal em #{page.current_path}"
  end
end
