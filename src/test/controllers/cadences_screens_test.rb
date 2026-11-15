require "test_helper"

# Telas da régua (21, revisão 1 das telas; R428 a R446): a lista, o diagrama de raias nas duas densidades e no modo de análise, as mudanças na régua
# desligada (na hora) e na ligada (pela conferência), as rodadas, os comandos, as peças, as tarefas, a ficha e a permissão 24.
class CadencesScreensTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include SegmentsTestHelper
  include CadencesTestHelper

  setup do
    @alfa = tenants(:alfa)
    @sms = make_piece(@alfa)
  end

  def entrar(user = users(:joana)) = post(session_path, params: { email_address: user.email_address, password: "senha-de-teste-1" })

  test "a lista, o diagrama confortável e compacto, e o aviso da última coluna sem fim" do
    cadence = make_cadence(@alfa, lanes: [ [ make_segment(@alfa, "Atraso longo", [ { "path" => "overdue_days", "op" => "gte", "value" => 30 } ]), {} ], [ nil, { 5 => [ { piece: @sms } ] } ] ])
    entrar
    get cadences_path, headers: TRECHO
    assert_select "th a", text: "Cobrança PF"
    assert_select "td", text: /Todos os dias, 9h30/
    assert_includes rotulos_do_menu, "Réguas"

    get cadence_path(cadence), headers: TRECHO
    assert_select "table.raias thead th.marca-do-eixo .momento", text: "D+5"
    assert_select "tr.raia", 2
    assert_select ".cartao-da-acao .rotulo-da-acao", text: "SMS · Lembrete atraso"
    assert_select ".aviso", text: /tem ação e não tem fim/
    assert_select "tr.raia[data-sem-acoes=true] small", text: /este público fica fora/

    get cadence_path(cadence, densidade: "compacta"), headers: TRECHO
    assert_select ".diagrama[data-densidade=compacta]"
    assert_select ".cartao-da-acao[title=?] .apenas-leitor-de-tela", "SMS · Lembrete atraso", text: "SMS · Lembrete atraso"

    get cadence_path(cadence, modo: "analise"), headers: TRECHO
    assert_select "p small", text: /ainda não tem rodada concluída/
  end

  test "R428 e R442: criar, incluir coluna, raia e ação na régua desligada valem na hora; ligar passa pela conferência e só vale ao confirmar" do
    make_contract(@alfa, "C-77", bills: [ { overdue: 5 } ])
    entrar
    post cadences_path, params: { cadence: { tenant_id: @alfa.id, name: "Nova", milestone: "contract_arrears", schedule_days: [ "", "1", "2" ], schedule_time: "10:00",
                                             valid_from: Date.current.iso8601 } }, headers: TRECHO
    cadence = Cadence.find_by!(name: "Nova")
    assert_equal [ [ 1, 2 ], false ], [ cadence.schedule_days, cadence.enabled? ]

    post cadence_columns_path(cadence), params: { column: { offset: "5" } }, headers: TRECHO
    column = cadence.columns.reload.first
    get new_cadence_cell_path(cadence, raia: cadence.default_lane.id, coluna: column.id), headers: TRECHO
    assert_select ".escolha-do-tipo a", text: /SMS/
    get new_cadence_cell_path(cadence, raia: cadence.default_lane.id, coluna: column.id, tipo: "sms"), headers: TRECHO
    assert_select "select[name='cell[message_piece_id]'] option", text: "Lembrete atraso"
    post cadence_cells_path(cadence), params: { cell: { lane_id: cadence.default_lane.id, column_id: column.id, kind: "sms", message_piece_id: @sms.id } }, headers: TRECHO
    assert_equal 1, cadence.live_actions.count

    perform_enqueued_jobs { post enable_cadence_path(cadence), headers: TRECHO }
    review = evento_da_spa["navegar"]
    assert_match %r{\A/reguas/#{cadence.id}/conferencia}, review
    assert_not cadence.reload.enabled?, "nada muda até confirmar"
    get review, headers: TRECHO
    assert_select ".numeros-da-conferencia dd", text: "1"
    token = Rack::Utils.parse_query(URI(review).query)["token"]
    post confirm_cadence_path(cadence, token: token), headers: TRECHO
    assert cadence.reload.enabled?
    assert Change.exists?(subject_type: "cadence", subject_id: cadence.id, event: "enabled")

    post disable_cadence_path(cadence), headers: TRECHO
    assert_not cadence.reload.enabled?, "desligar vale na hora"
  end

  test "rodadas e comandos, com o detalhe e os filtros em português" do
    travel_to Time.zone.local(2026, 12, 15, 9, 31)
    make_contract(@alfa, "C-77", bills: [ { overdue: 5 } ])
    cadence = make_cadence(@alfa, lanes: [ [ nil, { 5 => [ { piece: @sms } ] } ] ])
    run_rounds(@alfa)
    CadenceCommand.find_each { |command| Cadences::Executors.run(command) }
    entrar
    get cadence_rounds_path(cadence), headers: TRECHO
    assert_select "td .situacao", text: "concluída"
    assert_select ".detalhe-da-linha th", text: "SMS · Lembrete atraso"
    get cadence_commands_path(credor: @alfa.id, estado: "executado", tipo: "sms"), headers: TRECHO
    assert_select ".detalhe-da-linha td", text: "simulado: SMS · Lembrete atraso · C-77"
    get cadence_commands_path(credor: @alfa.id, estado: "falhou"), headers: TRECHO
    assert_select "p.vazio", text: "Nenhum comando com estes filtros."
  end

  test "R446: peças e tarefas, com o \"usado em\"" do
    make_cadence(@alfa, lanes: [ [ nil, { 5 => [ { piece: @sms } ] } ] ])
    entrar
    get settings_message_pieces_path, headers: TRECHO
    assert_select "td", text: "Cobrança PF"
    post settings_message_pieces_path(credor: @alfa.id), params: { message_piece: { name: "Segunda via", channel: "email", active: "1" } }, headers: TRECHO
    assert MessagePiece.exists?(tenant: @alfa, name: "Segunda via", channel: "email")
    post queues_queue_tasks_path(credor: @alfa.id), params: { queue_task: { name: "Ligar", instruction: "Oferecer o acordo.", due_days: "3", active: "1" } }, headers: TRECHO
    get queues_queue_tasks_path, headers: TRECHO
    assert_select "th", text: "Ligar"
  end

  test "R444: a ficha mostra a situação na régua e a pílula Régua na linha do tempo" do
    travel_to Time.zone.local(2026, 12, 15, 9, 31)
    contract = make_contract(@alfa, "C-77", bills: [ { overdue: 7 } ])
    customer = contract.customers.first
    make_cadence(@alfa, lanes: [ [ nil, { 5 => [ { piece: @sms } ], 15 => [ { piece: make_piece(@alfa, "Segunda via") } ] } ] ])
    run_rounds(@alfa)
    entrar
    get_ficha(customer)
    assert_select "#nas-reguas[data-spa-vivo-confere]"
    get customer_cadence_situation_path(customer), headers: TRECHO
    assert_select "#nas-reguas li", text: /Cobrança PF/
    assert_select "#nas-reguas small", text: /última coluna alcançada D\+5/
    assert_select "#nas-reguas small", text: /Próxima coluna com ação: D\+15, em 8 dias/
    get customer_timeline_path(customer, linha: "regua"), headers: TRECHO
    assert_select "li[data-evento=regua] strong", text: "SMS · Lembrete atraso"
  end

  test "R445: sem a permissão 24, a régua não abre e o envio direto é recusado" do
    cadence = make_cadence(@alfa, enabled: false, lanes: [ [ nil, { 5 => [ { piece: @sms } ] } ] ])
    entrar(users(:carlos))
    get cadences_path, headers: TRECHO
    assert_includes [ 403, 404 ], response.status
    post enable_cadence_path(cadence), headers: TRECHO
    assert_includes [ 403, 404 ], response.status
    assert_not cadence.reload.enabled?
    assert AccessEvent.where(user: users(:carlos), event: "access_denied").exists?
  end
end
