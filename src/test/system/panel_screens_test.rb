require "application_system_test_case"

# Mecanismo do painel compartilhado (design system, revisão 4, decisão 0022): um <dialog> no layout, aberto por htmx, em duas apresentações. Abrir, validação (422)
# dentro do painel, sucesso que fecha e atualiza a página, Esc, clique fora, foco inicial e retorno do foco, rolagem travada, axe e a página inteira sem JavaScript.
class PanelScreensSystemTest < ApplicationSystemTestCase
  setup do
    @alfa = tenants(:alfa)
    @maria = make_customer(@alfa)
    add_contact(@maria, "phone", "(11) 98765-4321")
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
    visit customer_path(@maria)
  end

  def abrir_corrigir_nome
    find("button.menu-de-linha[aria-label='Mais ações do cliente']").click
    click_link "Corrigir nome"
    assert_selector "dialog#painel[open]"
  end

  test "abre como painel lateral de 480 px, com o foco no primeiro campo, a rolagem do corpo travada e o axe limpo" do
    click_link "Registrar acionamento"
    assert_selector "dialog#painel[open][data-variant=drawer] form.painel"
    assert_equal "painel-titulo", find("dialog#painel")["aria-labelledby"]
    assert_selector "#painel-titulo", text: "Registrar acionamento"
    assert_equal "contact_attempt_channel", page.evaluate_script("document.activeElement.id")
    assert_equal 480, page.evaluate_script("Math.round(document.querySelector('dialog#painel').getBoundingClientRect().width)")
    assert_equal "hidden", page.evaluate_script("getComputedStyle(document.body).overflow")
    assert_acessivel
  end

  test "o modal pequeno tem 400 px e abre pelo menu da barra de página" do
    find("button.menu-de-linha[aria-label='Mais ações do cliente']").click
    click_link "Exportar dados"
    assert_selector "dialog#painel[open][data-variant=modal]"
    assert_equal 400, page.evaluate_script("Math.round(document.querySelector('dialog#painel').getBoundingClientRect().width)")
    assert_equal "export_reason", page.evaluate_script("document.activeElement.id")
    assert_acessivel
  end

  test "Esc fecha e o foco volta ao botão que abriu" do
    link = find_link("Registrar acionamento")
    link.click
    assert_selector "dialog#painel[open]"
    page.send_keys(:escape)
    assert_no_selector "dialog#painel[open]"
    assert_equal "Registrar acionamento", page.evaluate_script("document.activeElement.textContent.trim()")
    assert_equal "visible", page.evaluate_script("getComputedStyle(document.body).overflow")
  end

  test "clique fora fecha e Cancelar também" do
    click_link "Registrar acionamento"
    assert_selector "dialog#painel[open] form.painel"
    page.driver.browser.mouse.click(x: 100, y: 850) # no fundo escurecido, longe de qualquer link da página
    assert_no_selector "dialog#painel[open]"
    assert_current_path customer_path(@maria)
    click_link "Registrar acionamento"
    within("#painel") { click_button "Cancelar" }
    assert_no_selector "dialog#painel[open]"
  end

  test "o 422 refaz o formulário dentro do painel, com o erro e o que foi digitado" do
    abrir_corrigir_nome
    within("#painel") do
      fill_in "Nome", with: "x"
      page.execute_script("document.querySelector('#customer_name').value = '   '; document.querySelector('#customer_name').required = false")
      click_button "Corrigir nome"
      assert_selector "[role=alert]"
    end
    assert_selector "dialog#painel[open]"
    assert_acessivel
    assert_equal @maria.reload.name, "Maria Souza"
  end

  test "o sucesso fecha o painel, mostra o aviso e atualiza a página sem recarregar" do
    marcador = page.evaluate_script("window.__sem_recarregar = 1")
    abrir_corrigir_nome
    within("#painel") do
      fill_in "Nome", with: "Maria da Silva Souza"
      click_button "Corrigir nome"
    end
    assert_no_selector "dialog#painel[open]"
    assert_selector "#avisos-da-pagina", text: "Nome corrigido"
    assert_selector "h1", text: "Maria da Silva Souza"
    assert_equal 1, page.evaluate_script("window.__sem_recarregar")
    assert marcador
  end

  test "sem JavaScript a mesma rota é uma página inteira, com a barra de página e o formulário num cartão" do
    visit edit_customer_name_path(@maria)
    assert_selector "h1", text: "Corrigir nome"
    assert_selector "section.cartao form.painel"
    assert_no_selector "dialog[open]"
    assert_acessivel
    fill_in "Nome", with: "Maria Souza Lima"
    click_button "Corrigir nome"
    assert_selector "h1", text: "Maria Souza Lima"
  end
end
