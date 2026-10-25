require "application_system_test_case"

# Menu da aplicação: na tela larga fica sempre à mostra; na estreita fica fechado e abre pelo botão do cabeçalho (popover nativo).
class NavigationSystemTest < ApplicationSystemTestCase
  setup do
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
  end

  test "na tela larga o menu está à mostra e não há botão" do
    page.driver.resize(1440, 900)
    assert_selector "nav[aria-label=Menu] a", text: "Clientes"
    assert_no_selector "button.botao-menu"
  end

  test "na tela estreita o menu começa fechado, abre pelo botão, leva ao destino e fecha com Esc" do
    page.driver.resize(390, 800)
    visit root_path
    assert_no_selector "nav[aria-label=Menu]", visible: :visible
    find("button.botao-menu").click
    assert_selector "nav[aria-label=Menu] a", text: "Clientes"
    assert_acessivel
    assert_not page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")
    find("button.botao-menu").click
    assert_no_selector "nav[aria-label=Menu]", visible: :visible
    find("button.botao-menu").click
    click_link "Clientes"
    assert_selector "h1", text: "Clientes"
    assert_no_selector "nav[aria-label=Menu]", visible: :visible
  end
end
