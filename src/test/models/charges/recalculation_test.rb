require "test_helper"

# Valor atualizado gravado por credor (09, R164 a R176, R173, R173a): Maria ao centavo, regras diferentes por credor, dias antes do histórico,
# troca de segmento e a falha de um credor.
class ChargesRecalculationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @beta = tenants(:beta)
    seed_indexes!
    configure_charges(@alfa)
  end

  test "R164 a R169 e critério de aceite: o recálculo grava o valor de Maria (principal corrigido, multa, juros, honorários e atualizado)" do
    bill = make_bill(@alfa, due: DUE)
    assert_equal 1, recalc_values(@alfa)
    row = valuation_of(bill)
    assert_equal [ 100_000, 100_534, 2011, 3211, 0, 105_756, TODAY ], [ row.principal_cents, row.corrected_principal_cents, row.fine_cents, row.interest_cents, row.fees_cents, row.total_cents, row.calculated_on ]
  end

  test "R164: título a vencer, pago ou retirado não tem valor atualizado" do
    future = make_bill(@alfa, number: "F", due: TODAY + 10)
    paid = make_bill(@alfa, number: "P", due: DUE, status: :paid)
    withdrawn = make_bill(@alfa, number: "W", due: DUE, status: :withdrawn)
    active = make_bill(@alfa, number: "A", due: DUE)
    recalc_values(@alfa)
    assert_equal [ nil, nil, nil ], [ future, paid, withdrawn ].map { |bill| total_of(bill) }
    assert_equal 105_756, total_of(active)
  end

  test "critério de aceite (revisão 5): o mesmo título na Alfa e na Beta usa a regra de cada credor, e a memória diz de qual credor" do
    configure_charges(@beta, fine: 0, interest: 2, index: "none")
    alfa_bill = make_bill(@alfa, due: DUE)
    beta_bill = make_bill(@beta, due: DUE, document: PaymentsHelper::JOAO)
    recalc_values(@alfa)
    recalc_values(@beta)
    assert_equal 105_756, total_of(alfa_bill)
    assert_equal 100_000 + round_to_cents(100_000 * 0.02 * (16.0 / 31 + 2 + 21.0 / 31)), total_of(beta_bill)
    assert_equal 0, valuation_of(beta_bill).fine_cents
  end

  test "V10: o recálculo de um credor não grava nem apaga linhas de outro" do
    mine = make_bill(@alfa, due: DUE)
    other = make_bill(@beta, due: DUE, document: PaymentsHelper::JOAO)
    recalc_values(@beta)
    recalc_values(@alfa)
    assert_equal [ @alfa.id, @beta.id ], [ valuation_of(mine).tenant_id, valuation_of(other).tenant_id ]
    recalc_values(@alfa)
    assert_equal 1, BillValuation.where(tenant_id: @beta.id).count
  end

  test "R171 e R174a: a troca de segmento do contrato em 20/10 muda os juros dos dias seguintes; antes do histórico vale o primeiro segmento" do
    pf = make_segment(@alfa, "PF", person_type: "person", fine_pct: 2, interest_kind: "fixed", interest_pct: 2, index_code: "none")
    bill = make_bill(@alfa, due: DUE)
    contract = bill.contract
    first = Segment.catch_all_of(@alfa)
    ContractSegment.create!(contract: contract, segment: first, since: Date.new(2026, 10, 1))
    ContractSegment.create!(contract: contract, segment: pf, since: Date.new(2026, 10, 15))
    contract.update!(segment: pf)
    recalc_values(@alfa)
    months = 16.0 / 31 + 2 + 14.0 / 31 # de 15/07 a 14/10 a 1% (Demais, índice IPCA); depois, a 2% sem correção
    row = valuation_of(bill)
    assert_operator row.interest_cents, :>, round_to_cents(100_534 * 0.01 * months), "os dias depois da troca rendem mais que a 1%"
    assert_equal row.principal_cents, 100_000
  end

  test "R173: o recálculo registra a execução por credor, e a falha de um não impede o outro (R173a)" do
    configure_charges(@beta, fine: 0, interest: 0, index: "none")
    make_bill(@alfa, due: DUE)
    make_bill(@beta, due: DUE, document: PaymentsHelper::JOAO)
    failing = Charges::Recalculation.instance_method(:apply)
    Charges::Recalculation.define_method(:apply) { |**args| raise "falha simulada" if @tenant.name == "Escola Alfa"; failing.bind_call(self, **args) }
    begin
      [ @alfa, @beta ].each { |tenant| Charges::Recalculation.new(tenant).call(today: TODAY) }
    ensure
      Charges::Recalculation.define_method(:apply, failing)
    end
    alfa_run = TaskRun.where(tenant: @alfa, name: "values_recalculation").last
    assert_equal [ "failed", "RuntimeError" ], [ alfa_run.status, alfa_run.error_kind ]
    assert TaskRun.where(tenant: @beta, name: "values_recalculation").last.succeeded?
    assert_equal 1, BillValuation.where(tenant_id: @beta.id).count
    assert_equal 0, BillValuation.where(tenant_id: @alfa.id).count
  end

  test "R173: a falha não apaga o último valor calculado" do
    bill = make_bill(@alfa, due: DUE)
    recalc_values(@alfa)
    failing = Charges::Recalculation.instance_method(:apply)
    Charges::Recalculation.define_method(:apply) { |**| raise "falha simulada" }
    begin
      Charges::Recalculation.new(@alfa).call(today: TODAY + 1)
    ensure
      Charges::Recalculation.define_method(:apply, failing)
    end
    assert_equal 105_756, total_of(bill)
    status = Charges::Recalculation.status(@alfa)
    assert_equal [ TODAY, true ], [ status[:calculated_on], status[:last].failed? ]
  end

  test "R173: o job abre o registro (valores sendo recalculados), calcula e transmite o evento da aba Segmentos" do
    bill = make_bill(@alfa, due: DUE)
    run = nil
    assert_broadcasts(SegmentsChannel.broadcasting_for(@alfa), 2) do
      travel_to TODAY.in_time_zone.change(hour: 6) do
        run = Charges::Recalculation.start(@alfa, reason: "teste")
        assert Charges::Recalculation.status(@alfa)[:running]
        ValuesRecalculationJob.perform_now(@alfa, run)
      end
    end
    assert_predicate run.reload, :succeeded?
    assert_not Charges::Recalculation.status(@alfa)[:running]
    assert_equal 105_756, total_of(bill)
  end

  test "caso de exceção: credor sem regra de encargos tem o atualizado igual ao principal" do
    bill = make_bill(@beta, due: DUE)
    recalc_values(@beta)
    assert_equal 100_000, total_of(bill)
  end

  private
    def round_to_cents(value) = Charges::Calculator.round_cents(value)
end
