require "application_system_test_case"

# Telas de acesso no navegador: usuários, perfis, senha e sino de avisos passam no axe, e o sino se refaz pelo htmx quando chega o
# evento do WebSocket (o adaptador de teste do Action Cable não entrega ao navegador, então o evento `cable:` é disparado na página).
class AccessScreensSystemTest < ApplicationSystemTestCase
  def sign_in(user)
    visit new_session_path
    fill_in "E-mail", with: user.email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "header .usuario"
  end

  test "usuários, ficha, novo usuário, perfis e senha passam no axe, com dois credores" do
    memberships(:ana_alfa).update!(profile: profiles(:alfa_manager))
    sign_in users(:ana)

    visit memberships_path
    assert_selector "h1", text: "Usuários"
    assert_selector "th", text: "Credor"
    assert_acessivel

    click_link "Carlos Lima"
    assert_selector "h1", text: "Carlos Lima"
    assert_acessivel
    click_button "Desativar o acesso"
    assert_selector "dialog[open]", text: "Desativar o acesso?"
    assert_acessivel
    within("dialog[open]") { click_button "Cancelar" }

    visit new_membership_path
    assert_selector "h1", text: "Novo usuário"
    assert_acessivel

    visit profiles_path
    assert_selector "h1", text: "Perfis"
    assert_acessivel

    visit new_profile_path
    assert_selector "input[type=checkbox]", count: 16
    assert_acessivel

    visit edit_password_path
    assert_selector "h1", text: "Trocar a senha"
    assert_acessivel
  end

  test "importação: a tabela de colunas e o botão da planilha-modelo aparecem e passam no axe" do
    sign_in users(:joana)

    visit new_import_path

    assert_selector "h2", text: "Colunas da planilha"
    assert_selector "tbody tr", count: 30
    assert_link "Baixar planilha modelo"
    assert_acessivel
  end

  test "o primeiro acesso com senha temporária leva à tela de definir a senha, que passa no axe" do
    users(:carlos).update!(temporary_password_until: 72.hours.from_now)
    sign_in users(:carlos)

    assert_selector "h1", text: "Defina sua senha"
    assert_no_selector "nav[aria-label=Menu]"
    assert_acessivel

    fill_in "Nova senha", with: "minha-senha-definitiva"
    fill_in "Repita a nova senha", with: "minha-senha-definitiva"
    click_button "Salvar a senha"
    assert_selector "h1", text: "Resumo da carteira"
  end

  test "o gestor cria o operador pela tela e vê a senha temporária uma única vez" do
    sign_in users(:joana)
    visit new_membership_path

    fill_in "E-mail", with: "joana.souza@credor.example"
    fill_in "Nome", with: "Joana de Souza"
    select "Operador", from: "Perfil"
    click_button "Salvar"

    assert_selector "[role=status]", text: "não será mostrada de novo"
    assert_acessivel
    visit memberships_path
    assert_no_selector "[role=status]", text: "não será mostrada de novo"
    assert_selector "tbody th a", text: "Joana de Souza"
  end

  test "o sino mostra o aviso novo quando o evento chega, sem recarregar a página, e marca como lido" do
    sign_in users(:carlos)
    assert_no_selector "#sino .contador"
    # O sino se refaz uma vez quando o WebSocket conecta; espera essa busca terminar para o evento do teste não correr contra ela.
    assert_selector "html[data-cable='conectado']"
    page.driver.wait_for_network_idle
    page.execute_script("window.marcaDaPagina = 1")

    Notice.create!(user: users(:carlos), kind: "linked_to_tenant", data: { tenant_name: "Clínica Beta", actor_name: "Ana Prado", profile_name: "Gestor" })
    page.execute_script("document.body.dispatchEvent(new CustomEvent('cable:notice-created'))")

    assert_selector "#sino .contador", text: "1"
    assert_equal 1, page.evaluate_script("window.marcaDaPagina")
    find("#sino summary").click
    assert_text "Ana Prado ligou você a Clínica Beta"
    assert_acessivel

    click_button "Marcar como lido"
    assert_no_selector "#sino .contador"
    assert_equal 0, users(:carlos).notices.unread.count
  end

  test "o e-mail muito longo não estoura o menu do usuário e o cabeçalho tem 56 px" do
    users(:joana).update!(email_address: "#{'nome.muito.longo.' * 6}joana@exemplo.com.br")
    sign_in users(:joana)
    page.driver.resize(1440, 900)
    assert_equal 56, page.evaluate_script("document.querySelector('body > header').getBoundingClientRect().height")
    find("header .usuario summary").click

    dentro = page.evaluate_script(<<~JS)
      (() => {
        const painel = document.querySelector("header .usuario[open] > div").getBoundingClientRect()
        const email = document.querySelector("header .usuario[open] > div p").getBoundingClientRect()
        return painel.right <= window.innerWidth && painel.left >= 0 && email.right <= painel.right + 1 && email.left >= painel.left - 1
      })()
    JS
    assert dentro, "o e-mail ou o painel saiu da janela"
    page.driver.resize(390, 800)
    assert page.evaluate_script("document.querySelector('header .usuario[open] > div').getBoundingClientRect().right <= window.innerWidth")
  end
end
