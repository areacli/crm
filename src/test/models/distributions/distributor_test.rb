require "test_helper"

# Distribuir, mudar e recolher (14, R311, R312, R317, R344): exclusividade no ato, por contrato; a distribuição à mão vence a da regra; o fim
# cancela as propostas não aceitas da operação; o fim do período encerra sozinho.
class Distributions::DistributorTest < ActiveSupport::TestCase
  setup do
    @alfa = tenants(:alfa)
    @gestor = users(:joana)
    @recupera = make_operation(@alfa)
    @fale = make_operation(@alfa, short_name: "Fale", cnpj: "11222333000181")
    @ana = make_customer(@alfa, document: FakeData.cpf(301), name: "Ana Lima", contract_code: "C-7")
    @c7 = Contract.find_by!(tenant: @alfa, code: "C-7")
  end

  def distributor = Distributions::Distributor.new(@gestor)

  test "R312: com a exclusividade, o contrato com outra operação no mesmo período é recusado; em período seguinte é aceito" do
    distributor.distribute(tenant: @alfa, operation: @fale, contract: @c7, starts_on: Date.current, ends_on: Date.current + 30)
    error = assert_raises(Distributions::Refused) { distributor.distribute(tenant: @alfa, operation: @recupera, customer: @ana, starts_on: Date.current + 10) }
    assert_match "Fale", error.message
    assert distributor.distribute(tenant: @alfa, operation: @recupera, contract: @c7, starts_on: Date.current + 31)
    @alfa.setting.update!(operation_exclusive: false)
    assert distributor.distribute(tenant: @alfa, operation: @recupera, customer: @ana, starts_on: Date.current)
  end

  test "R344: a distribuição à mão encerra a da regra no mesmo contrato" do
    rule = distributor.distribute(tenant: @alfa, operation: @fale, contract: @c7, source: "rule")
    distributor.distribute(tenant: @alfa, operation: @recupera, contract: @c7)
    assert_equal "manual_override", rule.reload.end_reason
  end

  test "R317: recolher cancela a proposta não aceita da operação" do
    customer, nf1, nf2 = agreement_scenario(@alfa)
    distribution = distributor.distribute(tenant: @alfa, operation: @recupera, contract: nf1.contract)
    proposal = create_proposal(customer, [ nf1, nf2 ])
    Agreement.where(id: proposal.id).update_all(operation_id: @recupera.id)
    Distributions::Closer.new(@gestor).close(distribution, reason: "performance")
    assert_equal "canceled", proposal.reload.state
    assert_match "desempenho", proposal.reason
  end

  test "R311: a tarefa diária encerra a distribuição cujo fim passou, com o motivo fim do período" do
    distribution = distributor.distribute(tenant: @alfa, operation: @recupera, contract: @c7, starts_on: Date.current - 10, ends_on: Date.current + 5)
    distribution.update_column(:ends_on, Date.current - 1)
    Distributions::Daily.new(@alfa).call
    assert_equal "period_end", distribution.reload.end_reason
  end

  test "operação com credenciamento suspenso não recebe distribuição" do
    Accreditation.find_by(tenant: @alfa, operation: @recupera).update!(status: "suspended")
    assert_raises(Distributions::Refused) { distributor.distribute(tenant: @alfa, operation: @recupera, contract: @c7) }
  end
end
