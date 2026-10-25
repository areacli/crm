require "test_helper"

# Reversão do acordo em dois passos (11, R239): marca, liquidações estornadas viram crédito aguardando alocação, conclusão, desistência e alocação do crédito.
class Agreements::ReversionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    @gestor = users(:joana)
    @contract = @nf1.contract
  end

  teardown { travel_back }

  def pay_on(day, number, cents, **options)
    travel_day(day)
    pay_lines([ pay_line(number, day, cents, **options) ])
  end

  def reversion = Agreements::Reversion.new(@gestor)

  test "R239: abrir a reversão estorna a liquidação da entrada: R$ 343,66 viram crédito aguardando alocação e o acordo fica marcado" do
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    reversion.open!(@agreement.reload, "registrado no devedor errado")

    assert_predicate @agreement.reload, :reversing?
    assert_equal({ "available" => 0, "awaiting" => 34_366, "blocked" => 0 }, @contract.credit_balances)
    assert_equal 0, @agreement.titles.sum(:paid_cents)
    assert_equal 34_366, Payment.find_by!(identifier: PaymentAllocation.first.payment.identifier).moved_to_credit_cents
    assert_equal 34_366, PaymentReversal.where("identifier LIKE 'LIQ-%'").sum(:from_bill_cents)
    assert_includes @agreement.events.pluck(:kind), "reversion_opened"
  end

  test "R239: concluir cancela os títulos de acordo, os originais voltam a ativos e o crédito segue aguardando alocação" do
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    reversion.open!(@agreement.reload, "devedor errado")
    reversion.conclude!(@agreement.reload)

    assert_predicate @agreement.reload, :state_canceled?
    assert_equal [ "canceled" ], @agreement.titles.map(&:status).uniq
    assert_equal [ "active" ], [ @nf1.reload.status, @nf2.reload.status ].uniq
    assert_equal 34_366, @contract.credit_balances["awaiting"]
    assert_equal 0, @contract.credit_cents
  end

  test "R239: a reversão é recusada com acordo novo aguardando efetivação sobre os títulos, e sem motivo" do
    assert_raises(Agreements::Refused) { reversion.open!(@agreement, " ") }
  end

  test "R239: pagamento com o número do acordo durante a marca vira crédito aguardando alocação e o acordo não quebra" do
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    reversion.open!(@agreement.reload, "erro")
    pay_on(Date.new(2026, 12, 7), "ACD-000001-01", 31_253)

    assert_equal 34_366 + 31_253, @contract.credit_balances["awaiting"]
    assert_predicate title("ACD-000001-01"), :active?
    travel_day(Date.new(2027, 3, 10))
    Agreements::Daily.new(@alfa).apply(today: Date.new(2027, 3, 10))
    assert_predicate @agreement.reload, :reversing?
    assert_not_predicate @agreement, :state_broken?
  end

  test "V4, padrão: desistir reaplica as liquidações e os pagamentos do intervalo; arquivo leva 'reversão desistida'" do
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    reversion.open!(@agreement.reload, "erro")
    pay_on(Date.new(2026, 12, 7), "ACD-000001-01", 31_253)
    reversion.desist!(@agreement.reload, today: Date.new(2026, 12, 8))

    assert_not_predicate @agreement.reload, :reversing?
    assert_predicate title("ACD-000001-00"), :paid?
    assert_predicate title("ACD-000001-01"), :paid?
    assert_equal 0, @contract.credit_balances["awaiting"]
    assert_includes @agreement.events.pluck(:kind), "reversion_desisted"
    assert_equal 0, PaymentReversal.where("identifier LIKE 'LIQ-%'").count
  end

  test "R239: o gestor aloca o crédito aguardando alocação em título do mesmo contrato, e não em outro contrato" do
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    reversion.open!(@agreement.reload, "erro")
    reversion.conclude!(@agreement.reload)
    travel_day(Date.new(2026, 11, 20))
    outcome = reversion.allocate_credit!(@contract, @nf2.reload, 10_000)

    assert_equal 10_000, outcome.applied
    assert_equal 24_366, @contract.credit_balances["awaiting"]
    other = make_bill(@alfa, number: "OUTRO-1", contract_code: "CT-OUTRO", document: PaymentsHelper::JOAO, name: "João")
    assert_raises(Agreements::Refused) { reversion.allocate_credit!(@contract, other, 1_000) }
  end

  test "R239a: crédito aguardando alocação se transfere a outro contrato, mas não durante a marca" do
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    reversion.open!(@agreement.reload, "erro")
    other = make_bill(@alfa, number: "OUTRO-1", contract_code: "CT-OUTRO", document: PaymentsHelper::JOAO, name: "João").contract
    assert_raises(Access::Refused) { Payments::CreditTransfer.new(@gestor).transfer(from: @contract, to: other, cents: 1_000, reason: "teste") }
    reversion.conclude!(@agreement.reload)
    Payments::CreditTransfer.new(@gestor).transfer(from: @contract, to: other, cents: 10_000, reason: "contrato certo")
    assert_equal 10_000, other.credit_cents
    assert_equal 24_366, @contract.credit_balances["awaiting"]
  end

  def title(number) = Bill.find_by!(number: number).reload
end
