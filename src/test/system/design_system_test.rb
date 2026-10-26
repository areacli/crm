require "application_system_test_case"

# Estados do design system (o documento do design system do projeto): a referência e a confirmação no painel passam no axe, a confirmação só
# age depois de confirmar e a página não rola na horizontal.
class DesignSystemSystemTest < ApplicationSystemTestCase
  test "a referência não tem violações de acessibilidade" do
    visit design_system_path

    assert_selector "h1", text: "Design system"
    assert_acessivel
  end

  test "a confirmação abre, cancela sem agir e confirma" do
    # A confirmação é uma rota do aplicativo e pede sessão (a referência em si é aberta).
    visit new_session_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "h1", text: "Resumo da carteira"
    visit design_system_path
    click_link "Apagar o exemplo"

    assert_selector "dialog#painel[open][data-variant=modal]", text: "O exemplo é apagado e não volta."
    assert_acessivel
    within("dialog[open]") { click_button "Cancelar" }
    assert_no_selector "dialog[open]"

    click_link "Apagar o exemplo"
    within("dialog[open]") { click_button "Apagar" }

    assert_current_path design_system_path
  end

  test "o ícone pequeno tem 16 px (a variante de botão não vaza para outros elementos)" do
    visit design_system_path

    assert_equal 16, page.evaluate_script("document.querySelector('.icone[data-size=small]').getBoundingClientRect().width")
  end

  test "a página não rola na horizontal em desktop nem em tela estreita" do
    visit design_system_path
    assert_not page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")

    page.driver.resize(390, 800)
    visit design_system_path
    assert_not page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth")
  end

  test "a entrada e a página inicial passam no axe" do
    visit new_session_path
    assert_selector "h1", text: "Entrar no CRM"
    assert_acessivel

    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"

    assert_selector "h1", text: "Resumo da carteira"
    assert_acessivel
  end
end
