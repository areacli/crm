require "application_system_test_case"

# Telas de acesso no navegador: usuários, perfis e a planilha-modelo nas abas da casca. A senha temporária e o sino são da casca (`spa_casca_test.rb`).
class AccessScreensSystemTest < ApplicationSystemTestCase
  # Na SPA (fase 7): usuários e perfis nas abas, a ficha do usuário com o nome e o perfil editáveis na linha, as ações em diálogos; o axe saiu da área interna
  # (plano, D7).
  test "usuários, ficha, novo usuário e perfis nas abas, com dois credores; o perfil se troca na linha" do
    memberships(:ana_alfa).update!(profile: profiles(:alfa_manager))
    entrar_na_casca users(:ana)

    abrir_aba memberships_path
    assert_selector ".aba-raiz h1", text: "Usuários", wait: 10
    assert_selector ".aba-raiz .datagrid-header", text: "Credor"

    within(".aba-raiz") { click_link "Carlos Lima", match: :first }
    assert_selector ".aba-raiz h1", text: "Carlos Lima", wait: 10
    within(find(".aba-raiz section.cartao", text: "Acesso em")) do
      find("button[aria-label='Editar perfil']").click
      find("form.inline-editando select").select("Gestor")
      click_button "Salvar"
    end
    assert_aviso "Perfil alterado."
    assert_equal "Gestor", memberships(:carlos_alfa).reload.profile.name
    find(".aba-raiz .cabecalho-da-pagina .botao", text: "Desativar o acesso").click
    no_dialogo { assert_text "deixa de operar" }
    send_keys :escape

    abrir_aba memberships_path
    find(".aba-raiz .cabecalho-da-pagina .botao", text: "Criar usuário").click
    no_dialogo do
      escolher "Credor", "Clínica Beta"
      assert_selector "[id=campo-perfil]", wait: 10
    end
    send_keys :escape

    abrir_aba profiles_path
    assert_selector ".aba-raiz h1", text: "Perfis", wait: 10
    find(".aba-raiz .cabecalho-da-pagina .botao", text: "Criar perfil").click
    assert_selector ".aba-raiz h1", text: "Novo perfil", wait: 10
    # 22 permissões, em quatro grupos, e a marca "disponível para operações" (14, R310).
    assert_selector ".aba-raiz input[type=checkbox]", count: 23
    assert_selector ".aba-raiz .grupos-de-permissoes legend", count: 4
  end

  test "importação: a tabela de colunas e o botão da planilha-modelo aparecem" do
    entrar_na_casca

    visit new_import_path # na SPA desde a fase 5

    assert_selector ".aba-raiz h2", text: "Colunas da planilha", wait: 15
    assert_selector ".aba-raiz .datagrid-view2 tr.datagrid-row", count: 30
    assert_link "Baixar planilha modelo"
  end

  test "o gestor cria o operador pela tela e vê a senha temporária uma única vez" do
    entrar_na_casca users(:joana)
    abrir_aba memberships_path
    find(".aba-raiz .cabecalho-da-pagina .botao", text: "Criar usuário", wait: 10).click
    no_dialogo do
      fill_in "E-mail", with: "joana.souza@credor.example"
      fill_in "Nome", with: "Joana de Souza"
      escolher "Perfil", "Operador"
    end
    gravar_dialogo

    # A lista se refaz com a senha, mostrada só nesta resposta.
    assert_selector ".aba-raiz [role=status]", text: "não será mostrada de novo", wait: 10
    assert_selector ".aba-raiz .datagrid-row", text: "Joana de Souza"
    find(".tabs-selected .tabs-close").click
    abrir_aba memberships_path
    assert_selector ".aba-raiz h1", text: "Usuários", wait: 10
    assert_no_selector ".aba-raiz [role=status]", text: "não será mostrada de novo"
  end

  # O nome no cabeçalho da casca encurta com reticências: o cabeçalho não sai da janela nem com um nome muito longo.
  test "o nome muito longo não estoura o cabeçalho da casca" do
    users(:joana).update!(name: "Joana #{'Sobrenome Muito Comprido ' * 6}")
    entrar_na_casca
    page.driver.resize(1440, 900)
    dentro = page.evaluate_script(<<~JS)
      (() => {
        const barra = document.querySelector(".barra-topo").getBoundingClientRect()
        const usuario = document.querySelector("#usuario").getBoundingClientRect()
        return usuario.right <= window.innerWidth && usuario.right <= barra.right + 1 && document.documentElement.scrollWidth <= window.innerWidth
      })()
    JS
    assert dentro, "o nome saiu do cabeçalho ou a página rolou na horizontal"
  end
end
