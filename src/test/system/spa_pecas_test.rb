require "application_system_test_case"
require_relative "../support/spa_test_helper"

# Fase 2 do port para a SPA em EasyUI (decisão 0028): as peças comuns na página de referência (só em desenvolvimento e teste) e o tempo real numa ficha.
class SpaPecasSystemTest < ApplicationSystemTestCase
  include SpaTestHelper

  def abrir_referencia
    entrar_na_casca(endereco: "/#/design-system")
    assert_selector ".referencia h1", text: "Design system"
  end

  test "cálculo à vista: calculando desde a tecla, ainda calculando, calculado; falta dado, recusa e falha desabilitam a ação" do
    abrir_referencia
    fill_in "Demora do servidor (s)", with: "4"
    assert_selector ".estado-do-calculo", text: "Calculando…"
    assert_button "Usar o resultado", disabled: true
    assert_selector ".resultado-do-calculo.desatualizado"
    assert_selector ".estado-do-calculo", text: "Ainda calculando…", wait: 5
    assert_selector ".estado-do-calculo", text: "Calculado às", wait: 8
    assert_button "Usar o resultado", disabled: false
    assert_selector ".resultado-do-calculo .kpi dd", text: "15,00"

    fill_in "Demora do servidor (s)", with: "0"
    fill_in "Valor A", with: ""
    assert_selector ".resultado-do-calculo", text: "Preencha os dois valores"
    assert_button "Usar o resultado", disabled: true

    fill_in "Valor A", with: "-1"
    assert_selector ".resultado-do-calculo", text: "não podem ser negativos"
    assert_button "Usar o resultado", disabled: true

    check "Falhar"
    assert_selector ".estado-do-calculo", text: "Não foi possível calcular"
    assert_no_selector ".resultado-do-calculo .kpi"
    uncheck "Falhar"
    fill_in "Valor A", with: "1"
    assert_selector ".resultado-do-calculo .kpi dd", text: "6,00"
  end

  test "só a última mudança conta: a resposta atrasada é descartada" do
    abrir_referencia
    fill_in "Demora do servidor (s)", with: "2"
    fill_in "Valor A", with: "100"
    sleep 0.7
    fill_in "Demora do servidor (s)", with: "0"
    fill_in "Valor A", with: "1"
    assert_selector ".resultado-do-calculo .kpi dd", text: "6,00", wait: 6
    sleep 2.5
    assert_selector ".resultado-do-calculo .kpi dd", text: "6,00"
  end

  # A aba refeita (pelo tempo real, por exemplo) e logo levada a outro endereço recebe duas respostas; a que chega por último não pode tomar o lugar da
  # mais recente. Aqui a carga do primeiro endereço demora 2 s (no navegador, para não depender da ordem do servidor de teste, que atende um pedido por vez) e a do segundo volta na hora.
  test "a carga atrasada de uma aba não toma o lugar da carga mais recente" do
    entrar_na_casca
    abrir_aba "/importacoes/nova?tipo=pagamentos"
    assert_selector ".aba-raiz h1", text: "Importar pagamentos", wait: 10
    esperar_os_pedidos
    page.execute_script(<<~JS)
      jQuery.ajaxTransport("+*", (opcoes) => {
        if (!opcoes.url.includes("tipo=pagamentos")) return undefined
        return { send: (_cabecalhos, terminar) => setTimeout(() => terminar(200, "success", { html: "<p>Resposta atrasada</p>" }), 2000), abort: () => {} }
      })
    JS
    page.execute_script("import('spa/abas').then((abas) => { abas.abrir('/importacoes/nova?tipo=pagamentos', { recarregar: true }); abas.abrir('/importacoes/nova?tipo=estornos') })")
    assert_selector ".aba-raiz h1", text: "Importar estornos", wait: 10
    sleep 2.5
    assert_selector ".aba-raiz h1", text: "Importar estornos"
    assert_no_selector ".aba-raiz .falha"
  end

  test "edição inline: Enter grava, Esc desiste, sair do campo não grava e o erro fica junto ao campo" do
    abrir_referencia
    find("[data-inline-editar]").click
    find("form.inline-editando input").send_keys([ :control, "a" ], :backspace, :enter)
    assert_selector ".inline-erro", text: "Informe o nome."
    find("form.inline-editando input").send_keys("Maria Souza", :enter)
    assert_selector ".inline-valor", text: "Maria Souza"

    find("[data-inline-editar]").click
    find("form.inline-editando input").send_keys([ :control, "a" ], "Outro nome")
    find(".referencia h1").click
    assert_selector "form.inline-editando"
    find("form.inline-editando input").send_keys(:escape)
    assert_no_selector "form.inline-editando"
    assert_selector ".inline-valor", text: "Maria Souza"
  end

  test "a data aparece em dd/mm/aaaa e vai ao servidor em aaaa-mm-dd" do
    abrir_referencia
    assert_selector ".datagrid-row", text: "<b data-invadido>Nome com marcação</b>"
    assert_no_selector "b[data-invadido]"
    assert_field "Data", with: "10/11/2026"
    assert_equal "2026-11-10", page.evaluate_script("jQuery('input[name=ref_data]').val()")
    # A data digitada (sem o calendário) vale ao sair do campo e no Enter.
    find_field("Data").fill_in(with: "25/12/2026")
    find_field("Data").send_keys(:tab)
    assert_equal "2026-12-25", page.evaluate_script("jQuery('input[name=ref_data]').val()")
    find_field("Data").fill_in(with: "01/02/2027")
    find_field("Data").send_keys(:enter)
    assert_field "Data", with: "01/02/2027"
    assert_equal "2027-02-01", page.evaluate_script("jQuery('input[name=ref_data]').val()")
  end

  test "espera na janela: carregando, ainda carregando e a resposta; falha com Tentar de novo" do
    abrir_referencia
    click_link "Ver resposta em 4 s"
    assert_selector ".janela-corpo .espera-texto", text: "Carregando…"
    assert_selector ".janela-corpo .espera-texto", text: "Ainda carregando…", wait: 5
    assert_selector ".janela-corpo", text: "Chegou depois de 4 s", wait: 6
    click_link "Ver falha"
    assert_selector ".janela-corpo .falha", text: "Não foi possível carregar"
    assert_button "Tentar de novo"
  end

  test "diálogo: 422 volta com o erro, a gravação demorada diz Ainda gravando e o sucesso fecha com o aviso" do
    abrir_referencia
    click_link "Abrir diálogo"
    within("form.dialogo") { click_button "Salvar nota" }
    assert_selector "form.dialogo .aviso", text: "Escreva a nota."
    within("form.dialogo") do
      fill_in "Nota", with: "ok"
      fill_in "Demora do servidor (s)", with: "4"
      click_button "Salvar nota"
    end
    assert_button "Salvar nota", disabled: true
    assert_selector "form.dialogo .espera-texto", text: "Ainda gravando…", wait: 5
    assert_no_selector "form.dialogo", wait: 6
    assert_selector ".messager-body", text: "Nota salva."
  end

  test "tempo real: a ficha visível se refaz; escondida, fica marcada e se refaz ao voltar" do
    alfa = tenants(:alfa)
    maria = customer_of(alfa, FakeData.cpf(811), "Maria Tempo Real")
    make_contract(alfa, "CT-TR", customers: [ maria ], bills: [ { overdue: 20, cents: 50_000 } ])
    entrar_na_casca
    abrir_aba(customer_path(maria))
    assert_selector ".ficha h1", text: "Maria Tempo Real"
    canal = { channel: "ContactAttemptsChannel", customer_id: maria.id }
    sleep 1.6

    page.execute_script("jQuery('.ficha').attr('data-marca', 'velha')")
    simular_evento(canal, { event: "contact-attempts-changed" })
    assert_no_selector ".ficha[data-marca]"
    assert_selector ".ficha h1", text: "Maria Tempo Real"

    sleep 1.6
    page.execute_script("jQuery('.ficha').attr('data-marca', 'velha')")
    aba("Resumo")
    simular_evento(canal, { event: "contact-attempts-changed" })
    aba("Maria Tempo Real")
    assert_no_selector ".ficha[data-marca]"
  end

  test "falha numa aba em segundo plano deixa a marca no título até a pessoa voltar" do
    entrar_na_casca
    derrubar("/clientes")
    page.execute_script("import('spa/abas').then((abas) => { abas.abrir('/clientes', { titulo: 'Clientes' }); jQuery('#abas').tabs('select', 0) })")
    assert_selector ".tabs-title .marca-de-falha"
    aba("Clientes")
    assert_no_selector ".tabs-title .marca-de-falha"
    assert_selector ".falha", text: "Não encontrado"
  end
end
