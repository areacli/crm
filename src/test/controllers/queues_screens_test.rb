require "test_helper"

# Telas das filas (15): enquadramento com conferência e confirmação, ajustes que valem na hora, grupos, estratégia, visão do gestor com
# "Liberar", o "Próximo" e o "Devolver" do operador, a faixa da ficha e as permissões (R357, R33).
class QueuesScreensTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include SegmentsTestHelper

  setup do
    @alfa = tenants(:alfa)
    @late = make_segment(@alfa, "Atraso", [ { "path" => "overdue_days", "op" => "gt", "value" => 0 } ])
  end

  def entrar(user) = post(session_path, params: { email_address: user.email_address, password: "senha-de-teste-1" })

  def with_queue
    queue = WorkQueue.create!(tenant: @alfa, subject: "contracts", name: "Fila A", segment: @late, position: 1)
    group = QueueGroup.create!(tenant: @alfa, name: "Manhã")
    QueueGroupUser.create!(queue_group: group, user: users(:carlos))
    QueueGroupQueue.create!(queue_group: group, work_queue: queue, position: 1)
    [ queue, group ]
  end

  test "R357: incluir um item passa pela conferência em segundo plano e só vale ao confirmar" do
    entrar(users(:joana))
    get queues_work_queues_path, headers: TRECHO
    assert_select "th", text: /Demais/
    make_contract(@alfa, "C-77", bills: [ { overdue: 40 } ])
    # Na SPA, a conferência toma o lugar do enquadramento na mesma aba.
    perform_enqueued_jobs do
      post queues_work_queues_path(sujeito: "contracts"), params: { queue: { segment_id: @late.id, name: "Fila A", delivers: "1", position: 0 } }, headers: TRECHO
    end
    assert_match %r{\A/filas/enquadramento/conferencia}, evento_da_spa["navegar"]
    assert evento_da_spa["mesma_aba"]
    conferencia = evento_da_spa["navegar"]
    get conferencia, headers: TRECHO
    assert_select "td", text: "Fila A"
    assert_select "a[data-mesma-aba]", text: "Descartar"
    assert_equal 0, WorkQueue.where(tenant: @alfa, name: "Fila A").count, "nada muda até confirmar"
    token = Rack::Utils.parse_query(URI(conferencia).query)["token"]
    perform_enqueued_jobs { post confirm_queues_work_queues_path(credor: @alfa.id, token: token), headers: TRECHO }
    assert_equal queues_work_queues_path(credor: @alfa.id), evento_da_spa["navegar"]
    queue = WorkQueue.find_by!(tenant: @alfa, name: "Fila A")
    assert_equal 1, QueuePlacement.where(work_queue: queue).count
  end

  test "R357: ordem, trava e intervalos valem na hora e ficam no histórico" do
    queue, = with_queue
    entrar(users(:joana))
    patch queues_queue_setting_path(queue), params: { queue: { order_by: "overdue_days", order_tiebreak: "", lock_minutes: 20, interval_no_contact_hours: "2",
                                                                 interval_third_party_hours: "24", interval_customer_hours: "72" } }, headers: TRECHO
    assert evento_da_spa["atualizar"]
    assert_equal [ "overdue_days", 20, 120 ], queue.reload.values_at(:order_by, :lock_minutes, :interval_no_contact_minutes)
    assert Change.where(event: "queue_settings_changed").exists?
  end

  test "R353 e R354: o operador pede Próximo, cai na ficha com a faixa, devolve; o gestor vê e libera" do
    queue, = with_queue
    contract = make_contract(@alfa, "C-77", bills: [ { overdue: 40 } ])
    Queues::Recalculation.new(@alfa).apply
    entrar(users(:carlos))
    get summary_path, headers: TRECHO
    # O botão saiu do cabeçalho a pedido do Paulo (02/11/2026); o pedido continua o mesmo.
    assert_select "form.proximo", count: 0
    post next_delivery_path
    assert_redirected_to customer_path(contract.customers.first, contrato: contract.id)
    get_ficha(contract.customers.first, contrato: contract.id)
    assert_select "p", text: /Da fila\s+Fila A/
    delete current_delivery_path
    assert_nil QueueDelivery.open.find_by(user: users(:carlos))
    post next_delivery_path
    delivery = QueueDelivery.open.find_by!(user: users(:carlos))
    entrar(users(:joana))
    get queues_board_path, headers: TRECHO
    assert_select "th", text: "Carlos Lima"
    post queues_release_path(delivery), headers: TRECHO
    assert evento_da_spa["atualizar"]
    assert_equal "released", delivery.reload.end_reason
    get queues_board_queue_path(queue), headers: TRECHO
    assert_select "th", text: "C-77"
  end

  test "R353: sem nada disponível, o Próximo volta com o motivo" do
    with_queue
    entrar(users(:carlos))
    post next_delivery_path, headers: TRECHO.merge("HTTP_REFERER" => summary_url)
    assert_response :no_content
    assert_match "Ninguém disponível nas suas filas agora", evento_da_spa["aviso"]
    assert_equal "danger", evento_da_spa["tom"]
  end

  test "R353: grupos e estratégia do operador pela tela" do
    queue, group = with_queue
    entrar(users(:joana))
    get queues_queue_groups_path, headers: TRECHO
    assert_select "td", text: /Fila A/
    patch queues_queue_group_path(group), params: { group: { name: "Manhã", user_ids: [ users(:carlos).id, users(:ana).id ], queue_positions: { queue.id.to_s => "1" } } }, headers: TRECHO
    assert evento_da_spa["atualizar"]
    assert_equal [ users(:ana), users(:carlos) ].sort_by(&:id), group.reload.users.sort_by(&:id)
    get edit_queues_queue_strategy_path(users(:carlos), credor: @alfa.id), headers: TRECHO
    assert_response :success
    assert_select "table.campos-em-tabela input[name='strategy[weights][#{queue.id}]']"
    patch queues_queue_strategy_path(users(:carlos), credor: @alfa.id), params: { strategy: { mode: "weighted", weights: { queue.id.to_s => "3" }, positions: { queue.id.to_s => "1" } } }, headers: TRECHO
    assert evento_da_spa["atualizar"]
    assert_equal [ "weighted", 3 ], [ QueueStrategy.for(users(:carlos)).mode, QueueStrategy.for(users(:carlos)).weight_of(queue.id) ]
  end

  test "R357, R33: sem a 21, as telas e os envios diretos são recusados" do
    queue, = with_queue
    entrar(users(:carlos))
    get queues_work_queues_path, headers: TRECHO
    assert_response :not_found
    patch queues_queue_setting_path(queue), params: { queue: { order_by: "overdue_days", lock_minutes: 5 } }
    assert_response :not_found
    assert_equal 15, queue.reload.lock_minutes
  end
end
