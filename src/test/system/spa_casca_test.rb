require "application_system_test_case"

# A casca da SPA em EasyUI (decisão 0028): na raiz, com a senha temporária e a troca de senha nela, o sino, o limite de abas, o menu inteiro abrindo e a busca
# do cabeçalho.
class SpaCascaSystemTest < ApplicationSystemTestCase
  SENHA = "senha-de-teste-1".freeze

  def entrar(usuario = users(:joana), senha: SENHA)
    visit root_path
    assert_selector "#entrada-form"
    fill_in "E-mail", with: usuario.email_address
    fill_in "Senha", with: senha
    click_button "Entrar"
  end

  def item_do_menu(rotulo) = find("#menu .tree-title", text: rotulo, exact_text: true)

  # Com CAPTURAS=1, guarda a tela em tmp/capturas (fotos da fase para o Paulo).
  def capturar(nome)
    page.save_screenshot(Rails.root.join("tmp/capturas/fase-1-#{nome}.png").to_s) if ENV["CAPTURAS"]
  end

  test "a raiz é a casca, com o Resumo fixo, e o menu inteiro abre aba com a tela ou o aviso" do
    entrar
    assert_selector "#usuario", text: users(:joana).name
    assert_selector ".tabs-title", text: "Resumo"
    assert_no_selector ".tabs-selected .tabs-close"
    assert_selector ".aba-raiz .kpis", wait: 10 # o Resumo já está na SPA (fase 4)

    grupos = all("#menu .accordion-header .panel-title").map(&:text)
    assert_equal "Geral", grupos.first
    grupos.drop(1).each do |grupo|
      find("#menu .accordion-header .panel-title", text: grupo, exact_text: true).click
      within(find("#menu .accordion-header .panel-title", text: grupo, exact_text: true).ancestor(".accordion > .panel")) do
        first(".tree-node:not(:has(.tree-hit.tree-collapsed)) .tree-title").click
      end
      assert_selector "#abas .tabs-panels .placeholder h2, #abas .tabs-panels .lista, #abas .tabs-panels .cabecalho-da-pagina h1", wait: 10
    end
  end

  test "senha temporária: a pessoa define a senha na entrada, antes de qualquer aba" do
    users(:carlos).update!(temporary_password_until: 72.hours.from_now)
    entrar users(:carlos)
    assert_selector "#definir-senha", text: "Defina sua senha"
    assert_no_selector ".tabs-title"
    capturar "definir-senha"

    fill_in "Nova senha", with: "curta"
    fill_in "Repita a nova senha", with: "curta"
    click_button "Salvar a senha"
    assert_selector "#definir-senha .aviso[data-tone='danger']"

    fill_in "Nova senha", with: "uma-senha-nova-e-longa-2026"
    fill_in "Repita a nova senha", with: "uma-senha-nova-e-longa-2026"
    click_button "Salvar a senha"
    assert_no_selector "#entrada"
    assert_selector "#usuario", text: users(:carlos).name
    assert_not users(:carlos).reload.temporary_password?
  end

  test "trocar a senha abre em diálogo e confirma" do
    entrar
    assert_selector "#usuario", text: users(:joana).name
    find("#usuario").click
    find("#menu-usuario .menu-text", text: "Trocar a senha").click
    within("form.dialogo") do
      fill_in "Senha atual", with: SENHA
      fill_in "Nova senha", with: "outra-senha-bem-longa-2026"
      fill_in "Repita a nova senha", with: "outra-senha-bem-longa-2026"
    end
    capturar "trocar-senha"
    within("form.dialogo") { click_button "Salvar a senha" }
    assert_no_selector "form.dialogo"
    assert_selector ".messager-body", text: I18n.t("passwords.update.done")
    assert users(:joana).reload.authenticate("outra-senha-bem-longa-2026")
  end

  test "o sino mostra o aviso novo e marca como lido" do
    entrar
    assert_selector "#usuario", text: users(:joana).name
    Notice.create!(user: users(:joana), kind: "linked_to_tenant", data: { tenant_name: "Clínica Beta", actor_name: "Ana Prado", profile_name: "Gestor" })
    # O teste não tem WebSocket entre servidor e navegador: o evento que o canal transmitiria é disparado na página.
    page.execute_script("jQuery(document).trigger('cable:notice-created')")
    assert_selector "#sino .contador", text: "1"
    find("#sino").click
    assert_selector ".avisos-da-janela li", count: 1
    click_button "Marcar como lido"
    assert_selector ".avisos-da-janela .vazio", text: "Nenhum aviso novo."
    assert_no_selector "#sino .contador"
  end

  test "com 12 abas de trabalho, a pessoa escolhe qual fechar e a nova abre" do
    entrar
    assert_selector "#usuario", text: users(:joana).name
    page.execute_script(<<~JS)
      import("spa/abas").then((abas) => {
        for (let i = 1; i <= 11; i++) { const reg = abas.abrir(`/acordos/${i}`, { titulo: `Acordo ${i}` }); reg.sujo = true }
      })
    JS
    assert_selector ".tabs-title", text: "Acordo 11"
    page.execute_script('import("spa/abas").then((abas) => abas.abrir("/clientes", { titulo: "Clientes" }))')
    assert_selector ".escolha-de-aba", text: "Escolha qual fechar"
    find(".escolha-de-aba label", text: "Acordo 3").click
    find(".dialog-button .l-btn", text: "Continuar").click
    assert_selector ".panel-title", text: "Descartar o que foi escrito?"
    find(".messager-button .l-btn", text: "Descartar").click
    assert_no_selector ".tabs-title", text: "Acordo 3", exact_text: true
    assert_selector ".tabs-title", text: "Clientes"
  end

  test "a busca do cabeçalho leva à lista de clientes filtrada" do
    customer_of(tenants(:alfa), FakeData.cpf(901), "Maria Buscada")
    entrar
    assert_selector "#usuario", text: users(:joana).name
    campo = find(".barra-topo .searchbox input.textbox-text")
    campo.fill_in(with: "Maria Buscada")
    campo.send_keys(:enter)
    assert_selector ".tabs-selected .tabs-title", text: "Clientes", wait: 10
    assert_selector ".lista .datagrid-view2 tr.datagrid-row", count: 1, wait: 15
    assert_field "Buscar", with: "Maria Buscada"
  end
end
