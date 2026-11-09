require "application_system_test_case"

# Operações no navegador (14): as telas do credor (credenciamento, distribuição, lote, enquadramento da distribuição, políticas, trilha) e as do
# usuário de operação (cabeçalho com a operação, lista e ficha só com o que está pra ele, pessoas da operação), sem rolagem horizontal; todas na SPA, fora do
# axe (plano, D7).
class OperationsScreensSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @operation = make_operation(@alfa)
    @caio = make_operation_user(@operation, @alfa, manager: true)
    @ana = make_customer(@alfa, document: FakeData.cpf(701), name: "Ana Distribuída", contract_code: "OP-1")
    @bia = make_customer(@alfa, document: FakeData.cpf(702), name: "Bia da Equipe", contract_code: "OP-2")
    Distributions::Distributor.new(users(:joana)).distribute(tenant: @alfa, operation: @operation, contract: Contract.find_by!(code: "OP-1"), exposure: "all",
                                                             starts_on: Date.current - 3)
    Operations::ReachBuilder.new(@alfa).rebuild
  end

  def entrar(user)
    entrar_na_casca(user)
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  # As telas do credor na SPA (fase 6 do port, decisão 0028): abas, com as ações em diálogos presos a elas. O axe saiu da área interna (plano, D7).
  test "as telas de operações do credor abrem nas abas, com os diálogos e sem rolar de lado" do
    entrar_na_casca users(:joana)

    abrir_aba settings_operations_path
    assert_selector ".aba-raiz h1", text: "Operações credenciadas", wait: 10
    assert_selector ".aba-raiz .datagrid-row", text: "Recupera"
    assert_selector ".aba-raiz .politica", text: "Exclusividade"
    sem_rolagem_horizontal
    find(".aba-raiz .cabecalho-da-pagina .botao", text: "Credenciar operação").click
    no_dialogo { assert_field "CNPJ" }
    send_keys :escape
    assert_no_selector ".dialogo-conteudo"

    within(".aba-raiz") { click_link "Recupera" }
    assert_selector ".aba-raiz h1", text: "Recupera", wait: 10
    assert_no_selector ".aba-raiz a", text: "Voltar para as operações credenciadas"

    abrir_aba distributions_path
    assert_selector ".aba-raiz h1", text: "Distribuição", wait: 10
    assert_selector "[id='resultado'] .datagrid-row", text: "OP-1"
    sem_rolagem_horizontal
    find(".aba-raiz .cabecalho-da-pagina .botao", text: /\ADistribuir\z/).click
    no_dialogo { assert_text "O que distribuir" }
    send_keys :escape

    abrir_aba new_distribution_batch_path
    assert_selector ".aba-raiz h1", text: "Distribuir em lote", wait: 10

    abrir_aba settings_distribution_rules_path(credor: @alfa.id)
    assert_selector ".aba-raiz h1", text: "Enquadramento da distribuição", wait: 10

    abrir_aba settings_operation_trails_path
    assert_selector ".aba-raiz h1", text: "Trilha das operações", wait: 10

    abrir_ficha @ana
    assert_selector ".aba-raiz ul.operacoes-do-contrato", text: "Recupera"
  end

  # Lote pela SPA (14, R316): a planilha só aparece para "Uma planilha"; a recusa volta na tela, com a mensagem; o lote abre na aba dele e a
  # conferência chega pelo tempo real; "Confirmar o lote" cria as distribuições sem sair da aba.
  test "o lote de um segmento: conferir, ver o que vai e confirmar, na aba do lote" do
    segment = make_segment(@alfa, "Todos os contratos", [ { "path" => "balance", "op" => "gt", "value" => 0 } ])
    entrar_na_casca users(:joana)
    abrir_aba new_distribution_batch_path
    assert_selector ".aba-raiz h1", text: "Distribuir em lote", wait: 10
    assert_no_selector ".aba-raiz .filebox"
    choose "Uma planilha"
    assert_selector ".aba-raiz .filebox"
    assert_no_selector ".aba-raiz label", text: "Segmento"
    choose "Um segmento"
    click_button "Conferir o lote"
    assert_selector ".aba-raiz .aviso", text: "Escolha um segmento ativo.", wait: 10

    escolher "Segmento", segment.name
    perform_enqueued_jobs(only: DistributionBatchJob) { click_button "Conferir o lote"; assert_aviso "Lote recebido. A conferência começou." }
    assert_selector "#abas .tabs-selected .tabs-title", text: "Lote de distribuição à Recupera", wait: 10
    sleep 1.6 # a aba ignora a rajada logo depois de se refazer
    simular_evento({ channel: "DistributionsChannel", tenant_id: @alfa.id }, { event: "distribution-batch-ready" })
    assert_selector ".aba-raiz #lote", text: /Vão \d+ contratos/, wait: 10
    perform_enqueued_jobs(only: DistributionBatchJob) { click_button "Confirmar o lote"; assert_aviso "Confirmação começou." }
    sleep 1.6
    simular_evento({ channel: "DistributionsChannel", tenant_id: @alfa.id }, { event: "distribution-batch-ready" })
    assert_selector ".aba-raiz #lote h2", text: "Lote confirmado", wait: 10
    assert Distribution.where(source: "batch").exists?
  end

  test "o usuário de operação vê o nome da operação no cabeçalho, só o cliente distribuído e as pessoas da operação" do
    entrar @caio
    assert_selector "#operacao-atual", text: "Recupera"

    # Clientes e a ficha estão na SPA (fase 3): a grade só traz o que está pra operação, e a ficha de fora responde como não encontrada.
    visit customers_path
    assert_selector ".lista .datagrid-row", text: "Ana Distribuída"
    assert_no_text "Bia da Equipe"

    find(".lista .datagrid-row a", text: "Ana Distribuída").click
    assert_selector ".aba-raiz .cabecalho-da-pagina h1", text: "Ana Distribuída"

    visit customer_path(@bia)
    assert_selector ".aba-raiz .falha", text: "Não encontrado", wait: 15
    assert_no_text "Bia da Equipe"

    # Pessoas da operação estão na SPA (fase 7), fora do axe (D7).
    visit operation_people_path
    assert_selector ".aba-raiz h1", text: "Pessoas da Recupera", wait: 15
    assert_selector ".aba-raiz .datagrid-row", text: "Caio"
  end
end
