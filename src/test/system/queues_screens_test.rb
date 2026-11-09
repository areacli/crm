require "application_system_test_case"

# Filas no navegador (15): enquadramento, ajustes, grupos, estratégia, visão do gestor e a fila; o "Próximo" no cabeçalho e a faixa da
# entrega na ficha, sem rolagem horizontal (o axe saiu da área interna, plano da SPA, D7).
class QueuesScreensSystemTest < ApplicationSystemTestCase
  include SegmentsTestHelper
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    late = make_segment(@alfa, "Atraso", [ { "path" => "overdue_days", "op" => "gt", "value" => 0 } ])
    @queue = WorkQueue.create!(tenant: @alfa, subject: "contracts", name: "Fila A", segment: late, position: 1)
    @group = QueueGroup.create!(tenant: @alfa, name: "Manhã")
    QueueGroupUser.create!(queue_group: @group, user: users(:carlos))
    QueueGroupQueue.create!(queue_group: @group, work_queue: @queue, position: 1)
    make_contract(@alfa, "FILA-1", bills: [ { overdue: 40 } ], customers: [ customer_of(@alfa, FakeData.cpf(811), "Maria da Fila") ])
    Queues::Recalculation.new(@alfa).apply
  end

  def entrar(user)
    entrar_na_casca(user)
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  # As telas das filas na SPA (fase 6 do port, decisão 0028): abas com as ações em diálogos presos a elas. O axe saiu da área interna (plano, D7).
  test "as telas das filas do gestor abrem nas abas, com os diálogos e sem rolar de lado" do
    entrar_na_casca users(:joana)
    abrir_aba queues_work_queues_path
    assert_selector ".aba-raiz h1", text: "Enquadramento das filas", wait: 10
    assert_selector ".aba-raiz .datagrid-row", text: "Fila A"
    sem_rolagem_horizontal

    menu_da_linha "Fila A", "Editar ordem e tempos"
    no_dialogo { assert_field "Trava (minutos)", with: "15" }
    within(".dialogo-conteudo footer") { click_on "Cancelar" }
    assert_no_selector ".dialogo-conteudo"

    find(".aba-raiz section", text: "Contratos").find(".botao", text: "Incluir item").click
    no_dialogo { assert_button "Conferir o impacto" }
    send_keys :escape
    assert_no_selector ".dialogo-conteudo"

    abrir_aba queues_queue_groups_path
    assert_selector ".aba-raiz .datagrid-row", text: "Manhã", wait: 10
    sem_rolagem_horizontal
    within(".aba-raiz .datagrid-row", text: "Manhã") { click_link "Carlos Lima" }
    no_dialogo { assert_selector "table.campos-em-tabela input[aria-label='Fila A: peso']" }
    send_keys :escape

    abrir_aba queues_board_path
    assert_selector ".aba-raiz h1", text: "Filas", wait: 10
    sem_rolagem_horizontal

    within(".aba-raiz") { click_link "Fila A" }
    assert_selector ".aba-raiz .datagrid-row", text: "FILA-1", wait: 10
    assert_no_selector ".aba-raiz a", text: "Voltar às filas"
  end

  # A conferência do impacto toma o lugar do enquadramento na mesma aba; "Descartar" volta a ele, e "Confirmar a mudança" grava e volta (R357).
  test "incluir um item leva à conferência na mesma aba, e confirmar volta ao enquadramento com o item" do
    make_segment(@alfa, "Atraso longo", [ { "path" => "overdue_days", "op" => "gt", "value" => 30 } ])
    entrar_na_casca users(:joana)
    abrir_aba queues_work_queues_path
    assert_selector ".aba-raiz .datagrid-row", text: "Fila A", wait: 10
    abas_antes = all("#abas .tabs-title").size

    find(".aba-raiz section", text: "Contratos").find(".botao", text: "Incluir item").click
    no_dialogo do
      escolher "Segmento", "Atraso longo"
      fill_in "Nome", with: "Fila B"
    end
    perform_enqueued_jobs(only: QueuesJob) { gravar_dialogo "Conferir o impacto" }
    assert_selector "#abas .tabs-selected .tabs-title", text: "Conferir o impacto", wait: 10
    assert_equal abas_antes, all("#abas .tabs-title").size # a mesma aba, não outra
    simular_evento({ channel: "QueuesChannel", tenant_id: @alfa.id }, { event: "queue-review-ready" })
    assert_selector ".aba-raiz button", text: "Confirmar a mudança", wait: 10

    click_link "Descartar"
    assert_selector "#abas .tabs-selected .tabs-title", text: "Enquadramento das filas", wait: 10
    assert_no_selector ".aba-raiz .datagrid-row", text: "Fila B"

    find(".aba-raiz section", text: "Contratos").find(".botao", text: "Incluir item").click
    no_dialogo do
      escolher "Segmento", "Atraso longo"
      fill_in "Nome", with: "Fila B"
    end
    perform_enqueued_jobs(only: QueuesJob) { gravar_dialogo "Conferir o impacto" }
    simular_evento({ channel: "QueuesChannel", tenant_id: @alfa.id }, { event: "queue-review-ready" })
    perform_enqueued_jobs { click_button "Confirmar a mudança" }
    assert_aviso(/./)
    assert_selector "#abas .tabs-selected .tabs-title", text: "Enquadramento das filas", wait: 10
    assert_selector ".aba-raiz .datagrid-row", text: "Fila B", wait: 10
  end

  # O botão "Próximo" saiu do cabeçalho a pedido do Paulo (02/11/2026) até se decidir onde ele fica; o pedido continua o mesmo (POST /fila/proximo).
  test "o operador pede Próximo, vê a faixa e devolve" do
    entrar users(:carlos)
    pedir_proximo
    # A ficha está na SPA (fase 3): o endereço leva à aba na casca, com a faixa da entrega.
    assert_selector ".aba-raiz .cabecalho-da-pagina h1", text: "Maria da Fila", wait: 15
    assert_selector ".ficha-avisos", text: "Da fila Fila A"
    click_button "Devolver"
    assert_aviso "Devolvido à fila."
    assert_no_selector ".ficha-avisos", text: "Da fila Fila A"
  end

  private
    def pedir_proximo
      page.execute_script(<<~JS, next_delivery_path)
        const formulario = document.createElement("form")
        formulario.method = "post"
        formulario.action = arguments[0]
        const meta = document.querySelector("meta[name=csrf-token]")
        if (meta) {
          const token = document.createElement("input")
          token.type = "hidden"
          token.name = "authenticity_token"
          token.value = meta.content
          formulario.append(token)
        }
        document.body.append(formulario)
        formulario.submit()
      JS
    end
end
