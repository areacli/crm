require "test_helper"

# 15, R354: dois operadores pedindo "Próximo" ao mesmo tempo nunca recebem o mesmo sujeito. Sem transação de teste: cada thread usa a sua
# conexão, como em produção, e a garantia vem dos índices únicos parciais e do `SKIP LOCKED`.
class QueuesConcurrencyTest < ActiveSupport::TestCase
  include SegmentsTestHelper

  self.use_transactional_tests = false

  setup do
    @alfa = tenants(:alfa)
    @users = [ users(:carlos), users(:ana) ]
    segment = make_segment(@alfa, "Concorrência #{SecureRandom.hex(3)}", [ { "path" => "overdue_days", "op" => "gt", "value" => 0 } ])
    @queue = WorkQueue.create!(tenant: @alfa, subject: "contracts", name: "Fila C", segment: segment, position: 1)
    @group = QueueGroup.create!(tenant: @alfa, name: "Concorrência")
    @users.each { |user| QueueGroupUser.create!(queue_group: @group, user: user) }
    QueueGroupQueue.create!(queue_group: @group, work_queue: @queue, position: 1)
    @contracts = 3.times.map { |index| make_contract(@alfa, "CC-#{SecureRandom.hex(3)}-#{index}", bills: [ { overdue: 40 } ]) }
    Queues::Recalculation.new(@alfa).apply
  end

  teardown do
    QueueDelivery.where(work_queue: @queue).delete_all
    QueuePlacement.where(tenant: @alfa).delete_all
    QueueGroup.where(id: @group.id).destroy_all
    WorkQueue.where(tenant: @alfa).delete_all
    @contracts.each do |contract|
      customers = contract.customers.to_a
      bills = Bill.where(contract: contract).pluck(:id)
      BillValueVersion.where(bill_id: bills).delete_all
      BillValuation.where(bill_id: bills).delete_all
      Bill.where(id: bills).delete_all
      ContractCustomer.where(contract: contract).delete_all
      ContractTier.where(contract_id: contract.id).delete_all
      contract.delete
      customers.each(&:delete)
    end
    Segment.where(tenant: @alfa).where("name like 'Concorrência%'").delete_all
  end

  test "R354: em 20 rodadas com dois pedidos simultâneos e um só contrato livre, nunca duas entregas abertas do mesmo contrato" do
    @contracts.drop(1).each { |contract| QueuePlacement.where(subject: "contracts", subject_id: contract.id).update_all(available_at: 1.day.from_now) }
    20.times do
      barrier = Concurrent::CyclicBarrier.new(2)
      results = @users.map do |user|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            barrier.wait
            Queues::NextDelivery.new(user).call.delivery
          end
        end
      end.map(&:value)
      assert_equal 1, results.compact.size, "um recebe, o outro fica sem"
      assert_equal 1, QueueDelivery.open.where(work_queue: @queue).count
      QueueDelivery.open.where(work_queue: @queue).update_all(ended_at: Time.current, end_reason: "returned")
    end
  end
end
