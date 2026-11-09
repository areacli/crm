require "application_system_test_case"
require_relative "../support/spa_test_helper"

# Fase 0 do port para a SPA em EasyUI (decisão 0028): entrada, menu, Clientes, ficha, título em janela e diálogo, com a espera pelo servidor (design system, 7.2).
class SpaProvaSystemTest < ApplicationSystemTestCase
  include SpaTestHelper

  setup do
    @alfa = tenants(:alfa)
    @maria = customer_of(@alfa, FakeData.cpf(801), "Maria Duas Contas")
    @contrato = make_contract(@alfa, "CT-PROVA", customers: [ @maria ], bills: [ { overdue: 40, cents: 120_000 }, { overdue: 10, cents: 33_000 } ])
  end

  def preencher_acionamento
    find(".ficha .acoes a", text: "Registrar acionamento").click
    assert_selector "form.dialogo"
    escolher "Canal", "Telefone"
    escolher "Resultado", result_of(@alfa, :voicemail).name
  end

  def abrir_clientes
    find("#menu .tree-title", text: "Clientes").click
    assert_selector ".datagrid-row a", text: "Maria Duas Contas"
  end

  def abrir_ficha
    abrir_clientes
    find(".datagrid-row a", text: "Maria Duas Contas").click
    assert_selector ".ficha h1", text: "Maria Duas Contas"
    assert_selector ".abas-internas .datagrid-row a"
  end

  test "a entrada recusa senha errada na própria casca e abre o menu pelas permissões" do
    visit root_path
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: "errada-errada"
    click_button "Entrar"
    assert_selector "#entrada-mensagem", text: I18n.t("sessions.invalid")

    fill_in "Senha", with: SENHA_DE_TESTE
    click_button "Entrar"
    assert_no_selector "#entrada-form"
    assert_selector "#usuario", text: users(:joana).name
    assert_selector ".tabs-title", text: "Resumo"
  end

  # Uma recusa que não é a da senha (a proteção de origem do Rails responde 422 em HTML) terminava com o botão girando para sempre.
  test "a entrada recusada com uma página de erro diz como terminou e libera o botão" do
    visit root_path
    assert_selector "#entrada-form"
    derrubar "^/sessao$"
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: SENHA_DE_TESTE
    click_button "Entrar"
    assert_selector "#entrada-mensagem", text: "O servidor recusou a entrada (erro 404)"
    assert_button "Entrar", disabled: false
  end

  test "lista, ficha, título em janela e acionamento em diálogo, cada um no seu lugar" do
    entrar_na_casca
    abrir_ficha
    assert_selector ".tabs-title", text: "Maria Duas Contas"
    assert_match %r{#/clientes/#{@maria.id}}, current_url

    first(".abas-internas .datagrid-row a").click
    assert_selector ".janela-corpo .kpis"
    assert_selector ".window-header .panel-title", text: "Título"

    preencher_acionamento
    fill_in "Texto (opcional)", with: "Tentativa pela SPA."

    assert_difference -> { ContactAttempt.count }, 1 do
      within("form.dialogo") { click_button "Registrar acionamento" }
      assert_no_selector "form.dialogo"
    end
    assert_selector ".messager-body", text: "Acionamento registrado."
  end

  test "a aba fica viva ao alternar, e janela e diálogo ficam presos a ela" do
    entrar_na_casca
    abrir_clientes
    fill_in "Buscar", with: "Maria"
    esperar_os_pedidos
    assert_selector ".datagrid-row", count: 1
    find(".datagrid-row a", text: "Maria Duas Contas").click
    assert_selector ".abas-internas .datagrid-row a"
    first(".abas-internas .datagrid-row a").click
    assert_selector ".janela-corpo .kpis"
    find(".ficha .acoes a", text: "Registrar acionamento").click
    assert_selector "form.dialogo"

    aba("Clientes")
    assert_no_selector ".janela-corpo .kpis"
    assert_no_selector "form.dialogo"
    assert_field "Buscar", with: "Maria"

    aba("Maria Duas Contas")
    assert_selector ".janela-corpo .kpis"
    assert_selector "form.dialogo"
  end

  test "as abas voltam ao recarregar e o endereço abre a aba certa" do
    entrar_na_casca
    abrir_ficha
    aba("Clientes")
    page.refresh
    assert_selector ".datagrid-row a", text: "Maria Duas Contas"
    assert_selector ".tabs-title", text: "Maria Duas Contas"
    aba("Maria Duas Contas")
    assert_selector ".ficha h1", text: "Maria Duas Contas"
    assert_match %r{#/clientes/#{@maria.id}}, current_url
  end

  test "aba com formulário a meio pede para descartar antes de fechar" do
    entrar_na_casca
    abrir_ficha
    find(".ficha .acoes a", text: "Registrar acionamento").click
    fill_in "Texto (opcional)", with: "A meio"
    find(".tabs-selected .tabs-close").click
    assert_selector ".panel-title", text: "Descartar o que foi escrito?"
    find(".messager-button .l-btn", text: "Descartar").click
    assert_no_selector ".tabs-title", text: "Maria Duas Contas"
  end

  test "nome de cliente com marcação não vira código em lista, aba e janela" do
    nome = %q(<img src=x onerror="window.__invadido=1">)
    cliente = customer_of(@alfa, FakeData.cpf(802), nome)
    make_contract(@alfa, "CT-XSS", customers: [ cliente ], bills: [ { overdue: 900, cents: 9_900_000 } ])
    entrar_na_casca
    abrir_clientes
    find(".datagrid-row a", text: nome).click
    assert_selector ".ficha h1", text: nome
    first(".abas-internas .datagrid-row a").click
    assert_selector ".janela-corpo .kpis"
    assert_nil page.evaluate_script("window.__invadido ?? null")
    assert_no_selector ".aba-raiz img[src='x'], .tabs-title img"
  end

  test "falha ao abrir mostra a mensagem e Tentar de novo no lugar do conteúdo" do
    entrar_na_casca
    abrir_clientes
    derrubar("/clientes/#{@maria.id}")
    find(".datagrid-row a", text: "Maria Duas Contas").click
    assert_selector ".falha", text: "Não encontrado"
    assert_button "Tentar de novo"
  end

  test "falha na lista tira as linhas antigas e oferece Tentar de novo" do
    entrar_na_casca
    abrir_clientes
    derrubar("/clientes.json")
    fill_in "Buscar", with: "Maria"
    assert_selector ".falha-da-grade", text: "Não encontrado"
    assert_no_selector ".datagrid-row a"
  end

  test "gravação sem resposta diz que não se sabe se gravou e mantém o que foi digitado" do
    entrar_na_casca
    abrir_ficha
    preencher_acionamento
    fill_in "Texto (opcional)", with: "Importante"
    derrubar("/acionamentos$", abortar: true)
    within("form.dialogo") { click_button "Registrar acionamento" }
    assert_selector ".falha-ao-gravar", text: "Confira se foi gravado antes de repetir"
    assert_field "Texto (opcional)", with: "Importante"
    assert_button "Registrar acionamento", disabled: false
  end

  test "campo obrigatório vazio volta com o erro no diálogo, sem gravar" do
    entrar_na_casca
    abrir_ficha
    find(".ficha .acoes a", text: "Registrar acionamento").click
    assert_selector "form.dialogo"
    fill_in "Texto (opcional)", with: "Faltou o canal"

    assert_no_difference -> { ContactAttempt.count } do
      within("form.dialogo") { click_button "Registrar acionamento" }
      assert_selector "form.dialogo .aviso[data-tone='danger']"
    end
    assert_field "Texto (opcional)", with: "Faltou o canal"
  end

  test "clique duplo em gravar faz um pedido só" do
    entrar_na_casca
    abrir_ficha
    preencher_acionamento
    page.execute_script("window.__pedidos = 0; jQuery(document).ajaxSend((_e, _x, o) => { if (o.type === 'POST') window.__pedidos += 1 }); const f = jQuery('form.dialogo'); f.trigger('submit'); f.trigger('submit')")
    assert_equal 1, page.evaluate_script("window.__pedidos")
  end

  test "sessão vencida abre a entrada por cima das abas, sem perder o que está nelas" do
    entrar_na_casca
    abrir_ficha
    find(".ficha .acoes a", text: "Registrar acionamento").click
    fill_in "Texto (opcional)", with: "Não perder"
    Session.delete_all
    aba("Clientes")
    find(".pagination-load", match: :first).click
    assert_selector "#entrada-mensagem", text: "A sessão terminou"
    fill_in "E-mail", with: users(:joana).email_address
    fill_in "Senha", with: SENHA_DE_TESTE
    click_button "Entrar"
    assert_no_selector "#entrada-form"
    aba("Maria Duas Contas")
    assert_field "Texto (opcional)", with: "Não perder"
  end

  test "celular vê o aviso antes de qualquer senha, e o EasyUI não carrega" do
    page.driver.browser.page.command("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 2, mobile: true)
    page.driver.browser.page.command("Emulation.setTouchEmulationEnabled", enabled: true)
    visit root_path
    assert_selector "#aviso-tela h1", text: "O CRM foi feito para telas maiores"
    assert_no_selector "#entrada-form"
    assert_nil page.evaluate_script("window.jQuery ?? null")
  ensure
    page.driver.browser.page.command("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.page.command("Emulation.setTouchEmulationEnabled", enabled: false)
  end

  test "janela estreita de computador entra com rolagem" do
    page.driver.resize(800, 700)
    entrar_na_casca
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :>=, 1024
    assert_no_selector "#aviso-tela h1"
  ensure
    page.driver.resize(1440, 900)
  end
end
