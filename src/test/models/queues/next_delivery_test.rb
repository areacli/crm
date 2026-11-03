require "test_helper"

# O "Próximo" (15, R353 a R356): entrega o primeiro disponível que ainda casa, uma por vez, travado; a estratégia do operador entre as filas;
# o acionamento encerra a entrega e põe o sujeito no intervalo; o retorno espera a hora.
class QueuesNextDeliveryTest < ActiveSupport::TestCase
  include SegmentsTestHelper

  setup do
    @alfa = tenants(:alfa)
    @carlos = users(:carlos)
    @ana = users(:ana)
    @late = make_segment(@alfa, "Atraso", [ { "path" => "overdue_days", "op" => "gt", "value" => 0 } ])
    @queue = WorkQueue.create!(tenant: @alfa, subject: "contracts", name: "Fila A", segment: @late, position: 1)
    @group = QueueGroup.create!(tenant: @alfa, name: "Manhã")
    [ @carlos, @ana ].each { |user| QueueGroupUser.create!(queue_group: @group, user: user) }
    QueueGroupQueue.create!(queue_group: @group, work_queue: @queue, position: 1)
  end

  def recalc = Queues::Recalculation.new(@alfa).apply
  def next_for(user) = Queues::NextDelivery.new(user).call

  def record(user, contract, kind_result = contact_results(:alfa_promised), return_at: nil)
    Contacts::Recorder.new(user).record(contract.customers.first, { channel: "phone", result_id: kind_result.id, contract_id: contract.id,
                                                                    return_at: return_at&.strftime("%Y-%m-%dT%H:%M") })
  end

  test "R353 e R354: entrega o primeiro da ordem, travado; outro operador recebe o seguinte; uma entrega por vez" do
    big = make_contract(@alfa, "C-77", bills: [ { overdue: 40, cents: 90_000 } ])
    small = make_contract(@alfa, "C-80", bills: [ { overdue: 40, cents: 10_000 } ])
    recalc
    first = next_for(@carlos).delivery
    assert_equal big.id, first.subject_id
    assert_in_delta 15.minutes.from_now, first.locked_until, 5
    assert_equal small.id, next_for(@ana).delivery.subject_id
    assert_equal first, next_for(@carlos).delivery, "com entrega aberta, o Próximo devolve a mesma"
  end

  test "R354: trava vencida volta à fila; Devolver devolve" do
    contract = make_contract(@alfa, "C-77", bills: [ { overdue: 40 } ])
    recalc
    delivery = next_for(@carlos).delivery
    delivery.update!(locked_until: 1.minute.ago)
    assert_equal contract.id, next_for(@ana).delivery.subject_id
    assert_equal "expired", delivery.reload.end_reason
    QueueDelivery.open.find_by(user: @ana).finish!("returned")
    assert_equal contract.id, next_for(@ana).delivery.subject_id
  end

  test "R353: sem nada disponível, diz o motivo; sem grupo também" do
    assert_equal :empty, next_for(@carlos).reason
    assert_equal :no_group, next_for(users(:joana)).reason
  end

  test "R356 e R354: o acionamento encerra a entrega e põe o contrato no intervalo; o retorno espera a hora" do
    contract = make_contract(@alfa, "C-77", bills: [ { overdue: 40 } ])
    recalc
    next_for(@carlos)
    record(@carlos, contract, return_at: 3.hours.from_now)
    assert_nil QueueDelivery.open.find_by(user: @carlos), "o acionamento encerrou a entrega"
    placement = QueuePlacement.find_by(subject: "contracts", subject_id: contract.id)
    assert_in_delta 3.hours.from_now, placement.available_at, 60
    assert_equal :empty, next_for(@ana).reason
    placement.update!(available_at: 1.minute.ago)
    assert_equal contract.id, next_for(@ana).delivery.subject_id
  end

  test "R356: sem retorno, vale o intervalo do tipo do resultado" do
    contract = make_contract(@alfa, "C-77", bills: [ { overdue: 40 } ])
    recalc
    result = contact_results(:alfa_promised)
    record(@carlos, contract, result)
    placement = QueuePlacement.find_by(subject: "contracts", subject_id: contract.id)
    assert_in_delta @queue.interval_after(result.kind).from_now, placement.available_at, 60
  end

  test "R351: na entrega, quem não casa mais é pulado e muda de item" do
    paid = make_contract(@alfa, "C-1", bills: [ { overdue: 40, cents: 90_000 } ])
    other = make_contract(@alfa, "C-2", bills: [ { overdue: 40, cents: 10_000 } ])
    recalc
    paid.bills.update_all(status: "paid")
    assert_equal other.id, next_for(@carlos).delivery.subject_id
    assert_nil QueuePlacement.find_by(subject: "contracts", subject_id: paid.id).work_queue_id
  end

  test "R353: pesos 3 e 1 dão três entregas da primeira fila e uma da segunda" do
    b_segment = make_segment(@alfa, "Atraso longo", [ { "path" => "overdue_days", "op" => "gt", "value" => 100 } ])
    queue_b = WorkQueue.create!(tenant: @alfa, subject: "contracts", name: "Fila B", segment: b_segment, position: 0)
    QueueGroupQueue.create!(queue_group: @group, work_queue: queue_b, position: 2)
    4.times { |index| make_contract(@alfa, "A-#{index}", bills: [ { overdue: 40 } ]) }
    4.times { |index| make_contract(@alfa, "B-#{index}", bills: [ { overdue: 200 } ]) }
    recalc
    QueueStrategy.create!(user: @carlos, mode: "weighted", entries: [ { "queue_id" => @queue.id, "weight" => 3 }, { "queue_id" => queue_b.id, "weight" => 1 } ])
    served = 4.times.map do
      delivery = next_for(@carlos).delivery
      delivery.finish!("returned")
      delivery.work_queue.name
    end
    assert_equal({ "Fila A" => 3, "Fila B" => 1 }, served.tally)
  end
end
