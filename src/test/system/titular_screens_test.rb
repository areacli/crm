require "application_system_test_case"

# Direitos do titular no navegador (07), nas abas da casca: na ficha, os diálogos de exportar e anonimizar; a página para imprimir fica fora da casca, no axe;
# a guarda de dados e o prazo numa aba que se refaz sozinha pelo WebSocket quando a tarefa roda.
class TitularScreensSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @maria = make_full_customer(@alfa, ended_on: Date.current - 5.years + 12.days, code: "CT-7")
    @joao = make_full_customer(@alfa, ended_on: Date.current - 9.years, document: PaymentsHelper::JOAO, name: "João Retido")
    Titular::Retainer.new(users(:joana)).retain(@joao, "ação judicial nº 77")
    TaskRun.create!(tenant: @alfa, name: "data_retention", status: "succeeded", started_at: 2.hours.ago, finished_at: 2.hours.ago, processed: 2)
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  # As ações do titular ficam no menu "⋯" da barra da página e abrem num diálogo de 400 px preso à aba.
  def abrir_acao(nome)
    entrar_na_casca
    abrir_ficha(@maria)
    mais_acoes nome
    assert_selector ".dialogo-conteudo form.dialogo"
    assert_equal 400, page.evaluate_script("document.querySelector('.dialogo-conteudo').closest('.window').offsetWidth").round(-1)
  end

  test "os diálogos de exportar e de anonimizar abrem e fecham presos à aba" do
    abrir_acao "Exportar dados"
    no_dialogo { click_button "Cancelar" }
    assert_no_selector ".dialogo-conteudo"
    mais_acoes "Anonimizar"
    no_dialogo { assert_field "Documento do cliente" }
  end

  test "exportar termina com o link da página para imprimir, que abre noutra aba do navegador" do
    abrir_acao "Exportar dados"
    no_dialogo { fill_in "Motivo", with: "pedido do titular, protocolo 123" }
    gravar_dialogo "Exportar dados"
    link = find(".messager-body a", text: "Abrir a página para imprimir")
    assert_equal "_blank", link[:target]
    visit link[:href]
    assert_selector "h1", text: /Dados de Maria Souza mantidos por/
    assert_link "Baixar em JSON"
    assert_acessivel
    sem_rolagem_horizontal
  end

  test "anonimizar pelo diálogo, digitando o documento, e a ficha passa a mostrar a pílula, que abre a data" do
    abrir_acao "Anonimizar"
    no_dialogo do
      fill_in "Motivo", with: "pedido do titular, protocolo 123"
      fill_in "Documento do cliente", with: "529.982.247-25"
    end
    gravar_dialogo "Anonimizar cliente"
    # Padrões de interface, P28: o alerta do registro é a pílula do cabeçalho, sem faixa; o clique abre o texto.
    assert_no_selector ".aba-raiz .ficha-avisos .aviso"
    within(".aba-raiz .cabecalho-da-pagina") do
      click_button "Anonimizado"
      assert_selector ".definicao", text: "Cliente anonimizado em"
    end
    assert_selector "#abas .tabs-selected .tabs-title", text: "Cliente anonimizado nº #{@maria.id}"
    assert_equal "Cliente anonimizado nº #{@maria.id}", @maria.reload.name
  end

  # Na SPA (fase 7): a guarda numa aba, o reter num diálogo, e o aviso do canal refaz a aba; o axe saiu da área interna (plano, D7).
  test "a página de guarda abre na aba e se refaz sozinha quando a tarefa roda" do
    entrar_na_casca
    visit data_retention_path # o endereço antigo leva à aba na casca
    assert_selector ".aba-raiz h2", text: "Anonimização prevista nos próximos 30 dias", wait: 15
    assert_selector "section[aria-labelledby=previstos] .datagrid-row", text: "Maria Souza"
    assert_selector "section[aria-labelledby=retidos] .datagrid-row", text: "João Retido"
    find("section[aria-labelledby=previstos] .botao", text: "Reter", match: :first).click
    no_dialogo { assert_field "Motivo" }
    send_keys :escape
    assert_no_selector ".dialogo-conteudo"
    sem_rolagem_horizontal

    # O aviso do WebSocket refaz a aba sem recarregar a casca.
    assert_selector "section[aria-labelledby=execucoes] tr.datagrid-row", count: 1
    Titular::RetentionRun.new(@alfa).call
    sleep 1.6 # a aba que acabou de se refazer ignora avisos por 1,5 s (`spa/abas`, avisarMudanca): o da própria gravação não a refaz de novo
    simular_evento({ channel: "RetentionChannel", tenant_id: @alfa.id }, { event: "retention-changed" })
    assert_selector "section[aria-labelledby=execucoes] tr.datagrid-row", count: 2, wait: 10
  end

  test "o prazo de guarda, em Dados do credor, grava com o aviso e a aba refeita" do
    entrar_na_casca
    visit settings_tenant_registry_path
    assert_selector ".aba-raiz .politica .titulo", text: "Prazo de guarda dos dados", wait: 15
    within(find(".aba-raiz section.cartao", text: "Escola Alfa")) do
      find("input[name='retention[years]']").fill_in(with: "6")
      click_button "Salvar o prazo"
    end
    assert_aviso "Prazo de guarda de Escola Alfa salvo"
    assert_equal 6, @alfa.setting.reload.retention_years
  end
end
