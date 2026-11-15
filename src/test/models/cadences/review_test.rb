require "test_helper"

# Conferência do impacto da régua (21, R442) e a conferência única do segmento (R443; 13, R272, revisão 8).
class Cadences::ReviewTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SegmentsTestHelper
  include CadencesTestHelper

  setup do
    @tenant = tenants(:alfa)
    travel_to Time.zone.local(2026, 12, 15, 8, 0)
    @sms = make_piece(@tenant)
    @joana = users(:joana)
  end

  def contract(code, overdue:) = make_contract(@tenant, code, bills: [ { overdue: overdue } ])

  def review(cadence, operations)
    token = Cadences::Proposal.new(cadence, operations).token
    Cadences::Review.compute(@tenant, token)
    [ token, Cadences::Review.read(token) ]
  end

  test "critério 12: ligar mostra quem entra pela primeira coluna e quem entra no meio; a coluna vazia depois tira os antigos da conta" do
    contract("C-NEW", overdue: 2)
    [ 25, 45, 400 ].each { |days| contract("C-#{days}", overdue: days) }
    cadence = make_cadence(@tenant, enabled: false, lanes: [ [ nil, { 1 => [ { piece: @sms } ], 30 => [ { piece: make_piece(@tenant, "Último aviso") } ] } ] ])
    assert cadence.endless?
    assert Cadences::Editor.needs_review?(cadence, [ { "op" => "enable" } ])

    _token, result = review(cadence, [ { "op" => "enable" } ])
    # 2 e 25 dias: a última coluna alcançada é a D+1, a primeira; 45 e 400 dias: a D+30, no meio.
    assert_equal [ 2, 2 ], result.values_at("first_column", "middle")
    assert_equal 4, result["commands"]
    assert_equal 0, CadenceRound.count + CadenceDecision.count + CadenceCommand.count, "a conferência não grava nada"
    assert_not cadence.reload.enabled?

    cadence.columns.create!(offset_days: 60)
    _token, result = review(cadence, [ { "op" => "enable" } ])
    assert_equal [ 2, 1 ], result.values_at("first_column", "middle"), "com o fim em D+60, quem tem 400 dias sai da conta"
  end

  test "R442: a mudança na régua ligada vale só depois de confirmar; a conferência velha é recusada; tudo fica no histórico" do
    contract("C-1", overdue: 5)
    segment = make_segment(@tenant, "Atraso", [ { "path" => "overdue_days", "op" => "gte", "value" => 1 } ])
    cadence = make_cadence(@tenant, lanes: [ [ segment, {} ], [ nil, { 5 => [ { piece: @sms } ] } ] ])
    operations = [ { "op" => "add_column", "offset" => 3 } ]
    assert Cadences::Editor.needs_review?(cadence, operations)
    token, result = review(cadence, operations)
    assert result["slot"].present?
    assert_equal [ 5 ], cadence.reload.columns.map(&:offset_days)

    travel 1.second
    segment.update!(expression: { "all" => [ { "path" => "overdue_days", "op" => "gte", "value" => 2 } ] })
    assert_raises(Cadences::Refused) { Cadences::Applier.new(@joana).confirm(cadence, token) }

    token, = review(cadence, operations)
    Cadences::Applier.new(@joana).confirm(cadence, token)
    assert_equal [ 3, 5 ], cadence.reload.columns.map(&:offset_days)
    assert Change.exists?(subject_type: "cadence", subject_id: cadence.id, event: "column_added", after: "D+3", user_id: @joana.id)
    assert_raises(Cadences::Refused, "a mesma conferência não vale duas vezes") { Cadences::Applier.new(@joana).confirm(cadence, token) }
  end

  test "R442: desligar vale na hora, sem conferência; a régua desligada muda sem conferência" do
    cadence = make_cadence(@tenant, lanes: [ [ nil, { 5 => [ { piece: @sms } ] } ] ])
    assert_not Cadences::Editor.needs_review?(cadence, [ { "op" => "disable" } ])
    Cadences::Editor.new(cadence, actor: @joana).apply!([ { "op" => "disable" } ])
    assert_not cadence.reload.enabled?
    assert_not Cadences::Editor.needs_review?(cadence, [ { "op" => "add_column", "offset" => 10 } ])
    Cadences::Editor.new(cadence, actor: @joana).apply!([ { "op" => "add_column", "offset" => 10 }, { "op" => "update", "schedule_time" => "14:00" } ])
    assert_equal [ [ 5, 10 ], "14:00" ], [ cadence.reload.columns.map(&:offset_days), cadence.schedule_time ]
  end

  test "editor: raias antes da trilha padrão, mover, tirar; ação incluída e retirada; prioridade" do
    first = make_segment(@tenant, "A", [ { "path" => "overdue_days", "op" => "gte", "value" => 1 } ])
    second = make_segment(@tenant, "B", [ { "path" => "overdue_days", "op" => "gte", "value" => 2 } ])
    cadence = make_cadence(@tenant, enabled: false, lanes: [ [ nil, { 5 => [] } ] ])
    other = make_cadence(@tenant, name: "Outra", enabled: false)
    editor = Cadences::Editor.new(cadence, actor: @joana)
    editor.apply!([ { "op" => "add_lane", "segment_id" => first.id }, { "op" => "add_lane", "segment_id" => second.id } ])
    lane_b = cadence.lanes.reload.find { |lane| lane.segment_id == second.id }
    editor.apply!([ { "op" => "move_lane", "lane_id" => lane_b.id, "to" => 1 } ])
    assert_equal [ second.id, first.id, nil ], cadence.lanes.reload.map(&:segment_id)
    assert_raises(Cadences::Editor::Invalid) { editor.apply!([ { "op" => "remove_lane", "lane_id" => cadence.default_lane.id } ]) }

    column = cadence.columns.first
    editor.apply!([ { "op" => "add_action", "lane_id" => lane_b.id, "column_id" => column.id, "kind" => "sms", "message_piece_id" => @sms.id } ])
    action = lane_b.actions.reload.first
    editor.apply!([ { "op" => "remove_action", "action_id" => action.id } ])
    assert_empty lane_b.actions.reload
    assert action.reload.removed_at

    Cadences::Editor.new(other, actor: @joana).apply!([ { "op" => "move_priority", "to" => 1 } ])
    assert_equal [ other.id, cadence.id ], Cadence.where(tenant: @tenant).by_priority.pluck(:id)
  end

  test "R443: o segmento usado só numa régua e numa fila passa pela conferência única, com o efeito em cada processo" do
    late = contract("C-1", overdue: 40)
    contract("C-2", overdue: 10)
    segment = make_segment(@tenant, "Atraso 31+", [ { "path" => "overdue_days", "op" => "gte", "value" => 31 } ])
    make_cadence(@tenant, lanes: [ [ segment, { 5 => [ { piece: @sms } ] } ], [ nil, {} ] ])
    assert segment.used?
    assert_includes segment.other_uses, "Régua Cobrança PF, raia 1"

    changes = { segment.id.to_s => { "expression" => { "grammar" => 1, "subject" => "contracts", "all" => [ { "path" => "overdue_days", "op" => "gte", "value" => 5 } ] }, "active" => true } }
    rows = Segments::Impact.others(@tenant, changes)
    assert_equal [ { "process" => "cadences", "item" => "Cobrança PF", "before" => 1, "after" => 2 } ], rows
    assert_equal [ late.id ], Segments::Compiler.select(Segments::Compiler.new(@tenant).matching(segment.reload.expression_object)).map { |row| row["id"] },
                 "nada mudou fora da conferência"
  end
end
