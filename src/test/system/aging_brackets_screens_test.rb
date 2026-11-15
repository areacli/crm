require "application_system_test_case"

# Faixas de atraso no navegador (01, revisão 8): a lista editável da configuração (T6) e o filtro de credor do resumo, com as faixas padrão em todos os credores.
class AgingBracketsScreensSystemTest < ApplicationSystemTestCase
  test "Criar faixa e Excluir mudam a lista na hora, a prévia acompanha e o salvar grava" do
    entrar_na_casca
    abrir_aba(settings_portfolio_path, titulo: "Carteira")
    bloco = find("[data-faixas]", wait: 15)
    linhas = -> { bloco.all("tbody > tr").size }
    assert_equal 7, linhas.call # as 6 faixas padrão e uma em branco

    # Até 10 linhas; na décima, "Criar faixa" fica desligado.
    3.times { bloco.click_button "Criar faixa" }
    assert_equal 10, linhas.call
    assert bloco.find_button("Criar faixa", disabled: true).disabled?

    # Excluir tira a linha na hora; as três em branco saem, e a faixa 181–360 também.
    3.times { bloco.all("tbody > tr").last.click_button "Excluir" }
    bloco.find("input[aria-label='Faixa 7: de']").ancestor("tr").click_button "Excluir"
    bloco.find("input[aria-label='Faixa 5: de']").ancestor("tr").click_button "Excluir"
    assert_equal 5, linhas.call
    assert_not bloco.find_button("Criar faixa").disabled?

    # A prévia acompanha o que se digita, antes de salvar.
    bloco.find("input[aria-label='Faixa 5: de']").set("181")
    within(bloco.find("[data-previa-das-faixas]")) do
      assert_selector "li", text: "mais de 180 dias"
      assert_no_selector "li", text: "181–360 dias"
    end

    click_button "Salvar faixas" # o botão fica no rodapé do formulário, fora do bloco das faixas
    assert_text "Configuração de Escola Alfa salva.", wait: 15
    assert_equal [ 1, 31, 61, 91, 181 ], tenants(:alfa).setting.reload.aging_brackets.map { |faixa| faixa["from"] }
  end

  test "o resumo de todos os credores usa as faixas padrão, e o filtro de credor mostra as faixas dele" do
    tenants(:beta).setting.update!(aging_brackets: [ { from: 1, to: 60 }, { from: 61, to: nil } ])
    entrar_na_casca(users(:ana))
    within(".aba-raiz", text: "Resumo da carteira", wait: 15) do
      assert_text "Faixas padrão do sistema."
      assert_selector "td", text: "181–360"
    end

    escolher "Credor", "Clínica Beta"
    within(".aba-raiz", text: "Resumo da carteira") do
      assert_selector "td", text: "1–60", wait: 15
      assert_no_text "Faixas padrão do sistema."
      assert_no_selector "td", text: "181–360"
    end
  end
end
