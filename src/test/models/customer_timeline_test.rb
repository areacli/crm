require "test_helper"

# Linha do tempo da ficha (padrões de interface, revisão 24): atendimento (acionamentos com a promessa e propostas de acordo) e distribuição,
# o mais recente em cima, 10 por página, com o filtro por tipo e o contrato escolhido.
class CustomerTimelineTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2 = agreement_scenario(@alfa)
    @operation = make_operation(@alfa)
  end

  test "mistura acionamentos, propostas e distribuições em ordem, 10 por página, e filtra por tipo" do
    12.times { |index| insert_attempt(@customer, contacted_at: (index + 1).days.ago) }
    proposal = create_proposal(@customer, [ @nf1, @nf2 ])
    Distribution.create!(tenant: @alfa, operation: @operation, customer: @customer, exposure: "overdue", source: "manual", starts_on: Date.current - 5)

    timeline = CustomerTimeline.new(@customer)
    assert_equal 14, timeline.total
    assert_equal 2, timeline.pages
    first = timeline.events
    assert_equal 10, first.size
    assert_equal [ :agreement, proposal.id ], [ first.first.source, first.first.record.id ], "a proposta de agora é a mais recente"
    assert_equal first.map(&:at), first.map(&:at).sort.reverse
    assert_includes first.map(&:source), :distribution
    second = CustomerTimeline.new(@customer, page: 2).events
    assert_equal 4, second.size
    assert_empty first.map { |event| [ event.source, event.record.try(:id) || event.at ] } & second.map { |event| [ event.source, event.record.try(:id) || event.at ] }

    assert_equal [ :distribution ], CustomerTimeline.new(@customer, kind: "distribuicao").events.map(&:source)
    assert_equal 13, CustomerTimeline.new(@customer, kind: "atendimento").total
  end

  test "o usuário de operação não tem o filtro nem os eventos de distribuição" do
    Distribution.create!(tenant: @alfa, operation: @operation, customer: @customer, exposure: "overdue", source: "manual", starts_on: Date.current - 5)
    timeline = CustomerTimeline.new(@customer, kind: "distribuicao", distributions: false)
    assert_equal [ "atendimento" ], timeline.kinds
    assert_nil timeline.kind
    assert_not_includes timeline.events.map(&:source), :distribution
  end

  test "com o contrato escolhido, só os acionamentos daquele contrato" do
    other = Contract.create!(tenant: @alfa, code: "CT-OUTRO")
    # O acionamento é imutável (`readonly?`): o contrato vai direto na tabela.
    ContactAttempt.where(id: insert_attempt(@customer, contacted_at: 1.hour.ago).id).update_all(contract_id: other.id)
    ContactAttempt.where(id: insert_attempt(@customer, contacted_at: 2.hours.ago).id).update_all(contract_id: @nf1.contract_id)
    assert_equal [ @nf1.contract_id ], CustomerTimeline.new(@customer, contract: @nf1.contract, kind: "atendimento").events.map { |event| event.record.contract_id }
  end
end
