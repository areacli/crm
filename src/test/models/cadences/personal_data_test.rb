require "test_helper"

# Dados pessoais da régua (21, restrições; 07): a exportação traz os comandos do cliente, e a anonimização tira o vínculo com a pessoa.
class Cadences::PersonalDataTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SegmentsTestHelper
  include CadencesTestHelper
  include TitularHelper

  setup do
    @tenant = tenants(:alfa)
    travel_to Time.zone.local(2026, 12, 15, 9, 31)
  end

  test "exportação e anonimização dos comandos da régua" do
    ana = customer_of(@tenant, FakeData.cpf(91))
    contract = make_contract(@tenant, "C-91", bills: [ { overdue: 5 } ], customers: [ ana ])
    make_cadence(@tenant, lanes: [ [ nil, { 5 => [ { piece: make_piece(@tenant) } ] } ] ])
    make_cadence(@tenant, name: "Clientes", milestone: "customer_arrears", lanes: [ [ nil, { 5 => [ { piece: make_piece(@tenant, "Aviso ao cliente") } ] } ] ])
    run_rounds(@tenant)

    exported = Titular::Exporter.new(ana).to_h[:comandos_da_regua]
    assert_equal [ "Clientes", "Cobrança PF" ], exported.map { |row| row[:regua] }.sort
    assert_equal [ "SMS · Aviso ao cliente", "SMS · Lembrete atraso" ], exported.map { |row| row[:acao] }.sort

    Titular::Anonymizer.new(actor: users(:joana), reason: "teste", form: "screen").run(@tenant.id, [ ana.id ])
    assert_empty CadenceCommand.where(recipient_customer_id: ana.id)
    assert_empty CadenceCommandItem.where(customer_id: ana.id)
    assert_empty CadenceDecision.where(customer_id: ana.id)
    assert_equal 1, CadenceCommandItem.where(contract_id: contract.id).count, "o contrato do objeto continua, com tipo, estado e datas"
  end
end
