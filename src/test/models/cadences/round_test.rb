require "test_helper"

# A rodada da régua (21, R429, R431, R434 a R437; critérios de aceite): decisão, puladas, prioridade, destinatário, agrupamento, retomada e o
# despachante.
class Cadences::RoundTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SegmentsTestHelper
  include CadencesTestHelper

  setup do
    @tenant = tenants(:alfa)
    travel_to Time.zone.local(2026, 12, 15, 9, 31)
    @sms = make_piece(@tenant)
  end

  def contract(code, overdue:, customers: [], roles: {}) = make_contract(@tenant, code, bills: Array(overdue).map { |days| { overdue: days } }, customers: customers, roles: roles)

  def control_segment = make_segment(@tenant, "Controle", [ { "path" => "holder.draw", "op" => "lt", "value" => 10 } ])

  test "critério 1: SMS para o responsável financeiro de C-77; o titular do grupo de controle não recebe; o contrato em dia fica fora do episódio" do
    ana = customer_of(@tenant, FakeData.cpf(71))
    bia = customer_of(@tenant, FakeData.cpf(72))
    c77 = contract("C-77", overdue: 5, customers: [ ana, bia ], roles: { ana.id => [ "holder" ], bia.id => [ "financial_responsible" ] })
    c80 = contract("C-80", overdue: 5)
    contract("C-12", overdue: -10)
    ana.update_columns(draw: 42)
    bia.update_columns(draw: 42)
    c80.customers.first.update_columns(draw: 7)
    cadence = make_cadence(@tenant, lanes: [ [ control_segment, {} ], [ nil, { 5 => [ { kind: "sms", piece: @sms } ] } ] ])

    round = run_rounds(@tenant).fetch(cadence.id)
    assert round.completed?
    commands = CadenceCommand.where(cadence_round_id: round.id)
    assert_equal [ [ bia.id, [ c77.id ] ] ], commands.map { |command| [ command.recipient_customer_id, command.items.map(&:contract_id) ] }
    assert_equal 1, round.summary["out_of_episode"]
    assert_equal 3, round.summary["evaluated"]
    assert_enqueued_jobs 1, only: CadenceCommandJob
    assert commands.first.deadline_at > Time.current
  end

  test "critério 2: sem rodadas de D+2 a D+6, a de D+7 vale D+5; D+1 não sai de novo, e a coluna que ninguém viu fica pulada" do
    c77 = contract("C-77", overdue: 1)
    cadence = make_cadence(@tenant, lanes: [ [ nil, { 1 => [ { piece: @sms } ], 5 => [ { piece: make_piece(@tenant, "Segundo aviso") } ] } ] ])
    run_rounds(@tenant)
    assert_equal [ 1 ], items_of(cadence).map { |item| item.decision.column.offset_days }

    travel_to Time.current + 6.days
    run_rounds(@tenant)
    assert_equal [ 1, 5 ], items_of(cadence).map { |item| item.decision.column.offset_days }.sort
    assert_empty CadenceSkip.where(cadence: cadence), "D+1 disparou: não é pulada"

    late = contract("C-90", overdue: 9)
    travel_to Time.current + 1.day
    run_rounds(@tenant)
    assert_equal [ 1 ], CadenceSkip.where(cadence: cadence, object_key: "c#{late.id}").map { |skip| skip.column.offset_days }
    assert_equal 2, items_of(cadence).where(contract_id: c77.id).count, "nada sai pelos dias sem rodada"
  end

  test "R434: episódio novo começa a régua do início" do
    c77 = contract("C-77", overdue: 1)
    cadence = make_cadence(@tenant, lanes: [ [ nil, { 1 => [ { piece: @sms } ] } ] ])
    run_rounds(@tenant)
    bill = Bill.find_by!(contract: c77)
    bill.update!(status: "paid", paid_cents: bill.amount_cents, paid_on: Date.current)
    travel_to Time.current + 1.day
    ArrearsEpisode.refresh(@tenant, "contracts")
    Bill.create!(tenant: @tenant, contract: c77, customer: c77.customers.first, number: "N-2", due_date: Date.current - 1, amount_cents: 5_000)
    travel_to Time.current + 1.day
    run_rounds(@tenant)
    assert_equal 2, items_of(cadence).where(contract_id: c77.id).count
  end

  test "critério 3: a retomada não repete comando já posto na fila, e montar de novo não duplica" do
    3.times { |index| contract("C-#{index}", overdue: 5) }
    cadence = make_cadence(@tenant, lanes: [ [ nil, { 5 => [ { piece: @sms } ] } ] ])
    CadenceRound.create!(tenant: @tenant, cadence: cadence, scheduled_for: slot_today)
    round = Cadences::Round.new(@tenant, slot_today)
    round.decide
    round.prioritize
    round.build
    first = CadenceCommand.order(:id).first
    first.update!(enqueued_at: Time.current)
    round.build
    round.decide
    assert_equal 3, CadenceCommand.count
    round.enqueue
    assert_enqueued_jobs 2, only: CadenceCommandJob
    assert_equal 3, CadenceCommand.where.not(enqueued_at: nil).count
  end

  test "critério 6 e R436: um SMS para Ana com C-1 e C-2; a régua de menor prioridade no mesmo horário fica despriorizada no C-1" do
    ana = customer_of(@tenant, FakeData.cpf(81))
    c1 = contract("C-1", overdue: 5, customers: [ ana ])
    c2 = contract("C-2", overdue: 5, customers: [ ana ])
    first = make_cadence(@tenant, lanes: [ [ nil, { 5 => [ { piece: @sms } ] } ] ])
    # "Boas-vindas" (criação do contrato, D+0, com o fim em D+30): só o C-1, criado hoje, está em D+0.
    welcome = make_cadence(@tenant, name: "Boas-vindas", milestone: "contract_creation", lanes: [ [ nil, { 0 => [ { piece: make_piece(@tenant, "Bem-vindo") } ], 30 => [] } ] ])
    c1.update_columns(created_at: Time.current)

    rounds = run_rounds(@tenant)
    command = CadenceCommand.find_by!(cadence_round_id: rounds.fetch(first.id).id)
    assert_equal [ c1.id, c2.id ].sort, command.items.map(&:contract_id).sort
    lost = CadenceDecision.where(cadence: welcome)
    assert_equal [ [ c1.id, "deprioritized" ] ], lost.map { |decision| [ decision.contract_id, decision.state ] }
    assert_equal [ first.id ], lost.map(&:deprioritized_by_cadence_id).uniq
    assert_empty CadenceFiring.where(cadence: welcome), "despriorizado não conta como disparado"
  end

  test "critério 7 e R436: objetos diferentes no mesmo horário saem todos" do
    c1 = contract("C-1", overdue: [ 5, -1 ])
    make_cadence(@tenant, lanes: [ [ nil, { 5 => [ { piece: @sms } ] } ] ])
    # D+0 vazia é o fim (R430): sem ela, a D−1 valeria também para a fatura vencida há 5 dias.
    make_cadence(@tenant, name: "Mensalidades a vencer", milestone: "bill_due", lanes: [ [ nil, { -1 => [ { piece: make_piece(@tenant, "Vence amanhã") } ], 0 => [] } ] ])
    run_rounds(@tenant)
    assert_equal 2, CadenceCommandItem.where(contract_id: c1.id).count
    assert_equal 0, CadenceDecision.deprioritized.count
  end

  test "critério 8: no marco início do contrato, o contrato sem data conta como sem marco" do
    contract("C-40", overdue: 5)
    with_date = contract("C-41", overdue: 5)
    with_date.update!(started_on: Date.current - 10)
    cadence = make_cadence(@tenant, milestone: "contract_start", lanes: [ [ nil, { 10 => [ { piece: @sms } ] } ] ])
    round = run_rounds(@tenant).fetch(cadence.id)
    assert_equal 1, round.summary["without_milestone"]
    assert_equal [ with_date.id ], items_of(cadence).map(&:contract_id)
  end

  test "raia com segmento desativado: a rodada termina com falhas e quem não coube nas raias de cima não recebe nada" do
    contract("C-1", overdue: 5)
    segment = make_segment(@tenant, "Atraso", [ { "path" => "overdue_days", "op" => "gte", "value" => 1 } ])
    cadence = make_cadence(@tenant, lanes: [ [ segment, { 5 => [ { piece: @sms } ] } ], [ nil, { 5 => [ { piece: @sms } ] } ] ])
    segment.update!(active: false)
    round = run_rounds(@tenant).fetch(cadence.id)
    assert round.completed_with_failures?
    assert_equal "segmento desativado", round.summary.dig("lane_error", "reason")
    assert_equal 0, CadenceCommand.count
  end

  test "parâmetro inativo: a ação conta como parâmetro inativo e não gera comando" do
    contract("C-1", overdue: 5)
    cadence = make_cadence(@tenant, lanes: [ [ nil, { 5 => [ { piece: @sms } ] } ] ])
    @sms.update!(active: false)
    run_rounds(@tenant)
    assert_equal %w[inactive_parameter], CadenceDecision.where(cadence: cadence).map(&:state)
    assert_equal 0, CadenceCommand.count
  end

  test "despachante: atrasada no mesmo dia, falhou nos dias anteriores, sem rodar em feriado, e um job por credor e horário" do
    cadence = make_cadence(@tenant, lanes: [ [ nil, { 5 => [ { piece: @sms } ] } ] ], skip_national_holidays: true)
    cadence.update!(enabled_since: Time.zone.local(2026, 12, 10, 8))
    travel_to Time.zone.local(2026, 12, 15, 11, 2)
    CadencesDispatchJob.perform_now
    rounds = CadenceRound.where(cadence: cadence).order(:scheduled_for)
    assert_equal [ Date.new(2026, 12, 10), Date.new(2026, 12, 11), Date.new(2026, 12, 12), Date.new(2026, 12, 13), Date.new(2026, 12, 14), Date.new(2026, 12, 15) ],
                 rounds.map(&:day)
    assert_equal %w[failed] * 5 + %w[scheduled], rounds.map(&:state)
    assert rounds.last.late?
    assert_enqueued_jobs 1, only: CadenceRoundJob
    CadencesDispatchJob.perform_now
    assert_enqueued_jobs 1, only: CadenceRoundJob

    travel_to Time.zone.local(2026, 12, 25, 10)
    CadencesDispatchJob.perform_now
    assert_not CadenceRound.exists?(cadence: cadence, scheduled_for: Time.zone.local(2026, 12, 25, 9, 30)), "Natal: não roda"
  end

  test "R437: a régua com a vigência encerrada fica desligada, com o motivo" do
    cadence = make_cadence(@tenant, lanes: [ [ nil, { 5 => [ { piece: @sms } ] } ] ], valid_until: Date.current - 1)
    CadencesDispatchJob.perform_now
    assert_equal [ false, "vigência encerrada" ], [ cadence.reload.enabled?, cadence.disabled_reason ]
  end

  test "o job da rodada roda os quatro passos" do
    contract("C-1", overdue: 5)
    cadence = make_cadence(@tenant, lanes: [ [ nil, { 5 => [ { piece: @sms } ] } ] ])
    CadenceRound.create!(tenant: @tenant, cadence: cadence, scheduled_for: slot_today)
    CadenceRoundJob.perform_now(@tenant, slot_today.iso8601)
    assert CadenceRound.last.completed?
    assert_enqueued_jobs 1, only: CadenceCommandJob
  end
end
