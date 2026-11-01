require "test_helper"

# Linha do tempo das distribuições da ficha (padrões de interface, revisão 23): do passado até hoje, sem nada previsto.
class Distributions::TimelineTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @customer = make_customer(@alfa)
    @contract = @customer.contracts.first
    @operation = make_operation(@alfa)
  end

  def distribution(**attributes)
    Distribution.create!({ tenant: @alfa, operation: @operation, contract: @contract, exposure: "overdue", source: "manual" }.merge(attributes))
  end

  test "mostra entradas e saídas que já aconteceram, a mais recente em cima, e nada previsto" do
    distribution(starts_on: Date.current - 30, ends_on: Date.current - 10)
    distribution(starts_on: Date.current - 5, ends_on: Date.current + 20)
    distribution(starts_on: Date.current - 3, ended_at: Time.current, end_reason: "performance", customer: @customer, contract: nil)
    distribution(starts_on: Date.current + 7)

    events = Distributions::Timeline.for(@customer, [ @contract.id ])
    assert_equal [ [ Date.current, :exit ], [ Date.current - 3, :entry ], [ Date.current - 5, :entry ], [ Date.current - 10, :exit ], [ Date.current - 30, :entry ] ],
                 events.map { |event| [ event.date, event.kind ] }
    assert_equal "Desempenho", events.first.detail
    assert_equal "Fim do período", events[3].detail
    assert_equal "Contrato CT-1 · vencidas · à mão", events[2].detail
    assert events.all? { |event| event.date <= Date.current }
  end

  test "com o contrato escolhido, só as daquele contrato e as do cliente" do
    other = Contract.create!(tenant: @alfa, code: "CT-OUTRO")
    distribution(starts_on: Date.current - 2, contract: other)
    distribution(starts_on: Date.current - 1, customer: @customer, contract: nil)
    assert_equal [ "Cliente · vencidas · à mão" ], Distributions::Timeline.for(@customer, [ @contract.id ]).map(&:detail)
  end
end
