require "application_system_test_case"

# Filas no navegador (15): enquadramento, ajustes, grupos, estratégia, visão do gestor e a fila; o "Próximo" no cabeçalho e a faixa da
# entrega na ficha, todas no axe e sem rolagem horizontal.
class QueuesScreensSystemTest < ApplicationSystemTestCase
  include SegmentsTestHelper

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
    visit new_session_path
    fill_in "E-mail", with: user.email_address
    fill_in "Senha", with: "senha-de-teste-1"
    click_button "Entrar"
    assert_selector "header .usuario"
  end

  def sem_rolagem_horizontal = assert_not(page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth"))

  test "as telas das filas do gestor passam no axe" do
    entrar users(:joana)
    visit queues_work_queues_path
    assert_selector "h1", text: "Enquadramento das filas"
    assert_selector "th", text: "Fila A"
    assert_acessivel
    sem_rolagem_horizontal

    visit edit_queues_queue_setting_path(@queue)
    assert_selector "h1, h2", text: /Ordem e tempos/
    assert_acessivel

    visit new_queues_work_queue_path(tenant_id: @alfa.id, sujeito: "contracts")
    assert_selector "h1, h2", text: /Incluir item/
    assert_acessivel

    visit queues_queue_groups_path
    assert_selector "th", text: "Manhã"
    assert_acessivel
    sem_rolagem_horizontal

    visit edit_queues_queue_strategy_path(users(:carlos), tenant_id: @alfa.id)
    assert_selector "h1, h2", text: /Estratégia de Carlos/
    assert_acessivel

    visit queues_board_path
    assert_selector "h1", text: "Filas"
    assert_acessivel
    sem_rolagem_horizontal

    visit queues_board_queue_path(@queue)
    assert_selector "th", text: "FILA-1"
    assert_acessivel
  end

  # O botão "Próximo" saiu do cabeçalho a pedido do Paulo (02/11/2026) até se decidir onde ele fica; o pedido continua o mesmo (POST /fila/proximo).
  test "o operador pede Próximo, vê a faixa e devolve" do
    entrar users(:carlos)
    pedir_proximo
    assert_selector "h1", text: "Maria da Fila"
    assert_text "Da fila Fila A"
    assert_acessivel
    sem_rolagem_horizontal
    click_button "Devolver"
    assert_text "Devolvido à fila."
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
