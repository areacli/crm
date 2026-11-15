require "test_helper"

# O contrato do executor (21, R438 a R441, R447, R448): reservar, "ainda vale?", executar e devolver por item; simulado e emissão real.
class Cadences::ExecutorsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SegmentsTestHelper
  include CadencesTestHelper
  include PaymentAccountsHelper

  setup do
    @tenant = tenants(:alfa)
    travel_to Time.zone.local(2026, 12, 15, 9, 31)
    @sms = make_piece(@tenant)
  end

  def contract(code, overdue:) = make_contract(@tenant, code, bills: Array(overdue).map { |days| { overdue: days } })

  def run_commands = CadenceCommand.order(:id).each { |command| Cadences::Executors.run(command) }

  test "critério 9 e R440: o simulado pergunta \"ainda vale?\", registra e devolve executado; nada sai do CRM" do
    contract("C-77", overdue: 5)
    cadence = make_cadence(@tenant, lanes: [ [ nil, { 5 => [ { piece: @sms } ] } ] ])
    run_rounds(@tenant)
    run_commands
    item = items_of(cadence).first
    assert_equal [ "executed", "simulado: SMS · Lembrete atraso · C-77" ], [ item.state, item.detail ]
    assert_equal "executed", item.command.reload.state
  end

  test "a fila entrega ao menos uma vez: o segundo job do mesmo comando não faz nada" do
    contract("C-77", overdue: 5)
    cadence = make_cadence(@tenant, lanes: [ [ nil, { 5 => [ { piece: @sms } ] } ] ])
    run_rounds(@tenant)
    command = CadenceCommand.first
    Cadences::Executors.run(command)
    CadenceCommandItem.where(cadence_command_id: command.id).update_all(state: "queued", detail: nil)
    Cadences::Executors.run(command.reload)
    assert_equal %w[queued], items_of(cadence).map(&:state), "o comando já reservado não executa de novo"
  end

  test "critério 5 e R438: o título pago antes de o executor perguntar é descartado, com a hora" do
    c77 = contract("C-77", overdue: -3)
    cadence = make_cadence(@tenant, milestone: "bill_due", lanes: [ [ nil, { -3 => [ { piece: @sms } ], 0 => [] } ] ])
    run_rounds(@tenant)
    travel_to Time.zone.local(2026, 12, 15, 9, 33)
    bill = Bill.find_by!(contract: c77)
    bill.update!(status: "paid", paid_cents: bill.amount_cents, paid_on: Date.current)
    run_commands
    item = items_of(cadence).first
    assert_equal [ "discarded", "saiu do episódio: título pago às 9h33" ], [ item.state, item.reason ]
  end

  test "R438 e R434: régua desligada descarta e desfaz o disparo; mudou de raia também; a coluna volta a valer" do
    c77 = contract("C-77", overdue: 5)
    segment = make_segment(@tenant, "Atraso longo", [ { "path" => "overdue_days", "op" => "gte", "value" => 30 } ])
    cadence = make_cadence(@tenant, lanes: [ [ segment, {} ], [ nil, { 5 => [ { piece: @sms } ] } ] ])
    run_rounds(@tenant)
    cadence.update!(enabled: false)
    run_commands
    assert_equal [ "discarded", "régua desligada" ], items_of(cadence).first.slice(:state, :reason).values
    assert_empty CadenceFiring.where(cadence: cadence)

    cadence.update!(enabled: true)
    travel_to Time.current + 1.day
    run_rounds(@tenant)
    segment.update!(expression: { "all" => [ { "path" => "overdue_days", "op" => "gte", "value" => 1 } ] })
    run_commands
    moved = items_of(cadence).where(contract_id: c77.id).order(:id).last
    assert_equal [ "discarded", "mudou de raia: Atraso longo" ], [ moved.state, moved.reason ]
  end

  test "R439 e R437a: sem retorno depois do prazo; o retorno que chega depois vale" do
    contract("C-77", overdue: 5)
    cadence = make_cadence(@tenant, lanes: [ [ nil, { 5 => [ { piece: @sms } ] } ] ])
    run_rounds(@tenant)
    CadenceDeadlinesJob.perform_now(Time.current + 25.hours)
    item = items_of(cadence).first
    assert_equal [ "no_return", "no_return" ], [ item.state, item.command.reload.state ]
    assert Cadences::Returns.executed(item, "SMS entregue ao provedor")
    Cadences::Returns.refresh_command(item.command)
    assert_equal [ "executed", "executed" ], [ item.reload.state, item.command.reload.state ]
    assert_not Cadences::Returns.failed(item, "tarde demais"), "falhou é final, e executado também"
  end

  test "critério 10 e R447: emissão real pelo fornecedor falso; o contrato que já tem Pix vigente falha com o motivo da 16" do
    make_account(@tenant, modality: "pix", environment: "production", config: { "connection_result" => "ok", "pix_key" => "pix@alfa.com.br" })
    c77 = contract("C-77", overdue: 5)
    c80 = contract("C-80", overdue: 5)
    Payments::Issuer.new.issue_now(tenant: @tenant, kind: "pix", amount_cents: 1_000, customer: c80.customers.first, object: Bill.find_by!(contract: c80),
                                   due_on: Date.current + 3)
    action = { kind: "issue_instrument", payment_method: "pix", params: { "due_days" => 3, "object" => "overdue_bills" } }
    cadence = make_cadence(@tenant, lanes: [ [ nil, { 5 => [ action ] } ] ])
    run_rounds(@tenant)
    run_commands
    issued = items_of(cadence).find_by!(contract_id: c77.id)
    assert_equal "executed", issued.state
    assert_match(/\APix emitido, PIX-\d+\z/, issued.detail)
    assert_equal "rule", issued.payment_instrument.origin
    refused = items_of(cadence).find_by!(contract_id: c80.id)
    assert_equal [ "failed", "já tem Pix vigente" ], [ refused.state, refused.reason ]
  end

  test "critério 13 e R448: sem a carta há 10 dias ou mais, o contrato não está na raia de negativar e recebe a carta" do
    letter = make_piece(@tenant, "Carta aviso", channel: "letter")
    c77 = contract("C-77", overdue: 60)
    negativate = make_segment(@tenant, "Negativar", [ { "path" => "overdue_days", "op" => "gte", "value" => 60 },
                                                      { "path" => "commands", "quantifier" => "some", "older_than_days" => 10,
                                                        "where" => { "field" => "piece", "op" => "eq", "value" => letter.id } } ])
    cadence = make_cadence(@tenant, lanes: [ [ negativate, { 50 => [ { kind: "negativation" } ] } ],
                                             [ nil, { 50 => [ { kind: "letter", piece: letter } ] } ] ])
    run_rounds(@tenant)
    assert_equal [ "letter" ], items_of(cadence).where(contract_id: c77.id).map { |item| item.decision.kind }
    run_commands

    travel_to Time.current + 11.days
    expression = Segments::Expression.new(negativate.reload.expression)
    ids = ActiveRecord::Base.connection.select_all(*Segments::Compiler.new(@tenant).matching(expression).then { |query| [ query.sql, "Segments", query.binds ] }).map { |row| row["id"] }
    assert_equal [ c77.id ], ids, "a carta executada há 11 dias põe o contrato na raia de negativar"
  end
end
