require "test_helper"

# Configuração da régua (21, R428 a R433, R437, R437a, R446): régua, raias, colunas e ações, com os cadastros de peças e tarefas.
class Cadences::ConfigurationTest < ActiveSupport::TestCase
  include SegmentsTestHelper
  include PaymentAccountsHelper

  setup do
    @tenant = tenants(:alfa)
    @piece = MessagePiece.create!(tenant: @tenant, name: "Lembrete atraso", channel: "sms")
    @task = QueueTask.create!(tenant: @tenant, name: "Ligar para negociar", instruction: "Oferecer o acordo à vista.", due_days: 3)
  end

  def cadence(milestone: "contract_arrears", **options)
    Cadence.create!({ tenant: @tenant, name: "Cobrança PF #{SecureRandom.hex(2)}", milestone: milestone, schedule_days: [ 1, 2, 3, 4, 5 ], schedule_time: "09:30",
                      valid_from: Date.current }.merge(options))
  end

  def action(cadence, column, kind:, lane: cadence.default_lane, **attributes)
    CadenceAction.new({ lane: lane, column: column, kind: kind, position: 1 }.merge(attributes))
  end

  test "R428: a régua nasce desligada, no fim da prioridade, com a trilha padrão; o marco define o sujeito e não muda" do
    first = cadence
    second = cadence(milestone: "customer_registration")
    assert_not first.enabled?
    assert_equal [ first.position + 1, "customers" ], [ second.position, second.subject ]
    assert_equal [ true ], first.lanes.map(&:default?)

    assert_raises(ActiveRecord::ReadonlyAttributeError, "o marco não muda depois de criada") { first.update!(milestone: "bill_due") }
    duplicate = Cadence.new(tenant: @tenant, name: first.name, milestone: "bill_due", schedule_days: [ 1 ], schedule_time: "09:00", valid_from: Date.current)
    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:name, :taken)
  end

  test "R437: agenda de meia em meia hora, ao menos um dia, vigência em ordem; R437a: prazos de 1 a 720 horas por tipo" do
    record = Cadence.new(tenant: @tenant, name: "X", milestone: "bill_due", schedule_days: [], schedule_time: "09:15", valid_from: Date.current,
                         valid_until: Date.current - 1, return_hours: { "letter" => 0 })
    assert_not record.valid?
    assert_equal %i[schedule_days schedule_time valid_until return_hours].sort, record.errors.attribute_names.sort
    ok = cadence(return_hours: { "letter" => 120 })
    assert_equal [ 120, 24 ], [ Cadences::Catalog.return_hours(ok, "letter"), Cadences::Catalog.return_hours(ok, "sms") ]
    ok.valid_until = Date.current + 30
    assert ok.valid_on?(Date.current + 30)
    assert_not ok.valid_on?(Date.current + 31)
    assert_not ok.valid_on?(Date.current - 1)
  end

  test "R430: colunas sem repetição, na faixa do marco; a régua só liga com coluna com ação; a última com ação avisa que não tem fim" do
    record = cadence
    assert_not record.columns.build(offset_days: 0).valid?, "maior atraso aceita a partir de D+1"
    assert cadence(milestone: "bill_due").columns.build(offset_days: -5).valid?
    d5 = record.columns.create!(offset_days: 5)
    assert_not record.columns.build(offset_days: 5).valid?

    record.enabled = true
    assert_not record.valid?
    assert record.errors.of_kind?(:enabled, :without_actions)

    action(record, d5, kind: "sms", message_piece: @piece).save!
    assert record.reload.update(enabled: true)
    assert record.endless?
    record.columns.create!(offset_days: 60)
    assert_not record.reload.endless?
  end

  test "R431: raia com segmento do mesmo credor e do mesmo sujeito; a trilha padrão não tem segmento" do
    record = cadence
    contracts = make_segment(@tenant, "Atraso", [ { "path" => "overdue_days", "op" => "gte", "value" => 1 } ])
    customers = make_segment(@tenant, "Clientes PF", [ { "path" => "person_type", "op" => "eq", "value" => "person" } ], subject: "customers")
    other = make_segment(tenants(:beta), "Outro credor", [ { "path" => "overdue_days", "op" => "gte", "value" => 1 } ])
    assert record.lanes.build(segment: contracts, position: 2).valid?
    assert_not record.lanes.build(segment: customers, position: 2).valid?, "segmento de clientes numa régua de contratos"
    assert_not record.lanes.build(segment: other, position: 2).valid?
    assert_not record.lanes.build(position: 2).valid?, "só a trilha padrão fica sem segmento"
  end

  test "R431: a raia nova entra antes da trilha padrão, que continua por último" do
    record = cadence
    first = make_segment(@tenant, "Controle", [ { "path" => "holder.draw", "op" => "lt", "value" => 10 } ])
    second = make_segment(@tenant, "Atraso curto", [ { "path" => "overdue_days", "op" => "lte", "value" => 30 } ])
    record.add_lane!(second)
    record.add_lane!(first, at: 1)
    assert_equal [ [ 1, first.id ], [ 2, second.id ], [ 3, nil ] ], record.reload.lanes.map { |lane| [ lane.position, lane.segment_id ] }
  end

  test "R432 e R433: cada tipo com o seu parâmetro, ativo; a mesma ação não se repete na célula" do
    record = cadence
    column = record.columns.create!(offset_days: 5)
    email = MessagePiece.create!(tenant: @tenant, name: "Segunda via", channel: "email")

    assert_not action(record, column, kind: "sms").valid?, "SMS sem peça"
    assert_not action(record, column, kind: "sms", message_piece: email).valid?, "peça de outro canal"
    assert action(record, column, kind: "proposal", params: { "form" => "cash", "concession" => "max" }).valid?
    assert_not action(record, column, kind: "proposal", params: { "form" => "cash" }).valid?
    assert action(record, column, kind: "promise", params: { "value" => "overdue_only" }).valid?
    assert action(record, column, kind: "task", queue_task: @task).valid?
    measure = action(record, column, kind: "protest", params: { "lixo" => 1 })
    assert measure.valid?
    assert_equal({}, measure.params, "medida não tem parâmetro nesta versão")

    action(record, column, kind: "sms", message_piece: @piece).save!
    repeated = action(record, column, kind: "sms", message_piece: @piece)
    assert_not repeated.valid?
    assert repeated.errors.of_kind?(:base, :repeated_in_cell)

    @task.update!(active: false)
    assert_not action(record, column, kind: "task", queue_task: @task).valid?, "parâmetro inativo não entra"
  end

  test "R433: a emissão pede um meio com integração ativa, o vencimento e o objeto; no marco da fatura, o objeto é a própria fatura" do
    record = cadence
    column = record.columns.create!(offset_days: 5)
    pix = action(record, column, kind: "issue_instrument", payment_method: "boleto", params: { "due_days" => "3", "object" => "overdue_bills" })
    assert_not pix.valid?, "sem integração de boleto ativa"
    make_account(@tenant, modality: "boleto", environment: "production")
    assert pix.valid?, pix.errors.full_messages.to_sentence
    assert_equal({ "due_days" => 3, "object" => "overdue_bills", "reissue" => false }, pix.params)
    assert_not action(record, column, kind: "issue_instrument", payment_method: "boleto", params: { "due_days" => 3, "object" => "bill" }).valid?

    by_bill = cadence(milestone: "bill_due")
    due = by_bill.columns.create!(offset_days: -3)
    issued = action(by_bill, due, kind: "issue_instrument", payment_method: "boleto", params: { "due_days" => 0, "object" => "promise", "reissue" => "1" })
    assert issued.valid?
    assert_equal [ "bill", true ], issued.params.values_at("object", "reissue")
  end

  test "R432 e R446: a peça e a tarefa usadas numa régua não se apagam, mostram onde são usadas e ao desativar a ação fica com aviso" do
    record = cadence
    column = record.columns.create!(offset_days: 5)
    sms = action(record, column, kind: "sms", message_piece: @piece)
    sms.save!
    assert_equal [ record ], @piece.cadences.to_a
    assert_not @piece.destroy
    @piece.update!(active: false)
    assert_not sms.reload.active_parameter?
    assert sms.valid?, "a ação que já existe continua salva; a rodada a conta como parâmetro inativo"
  end
end
