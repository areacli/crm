require "test_helper"

# O crédito do contrato na tarefa diária (11, R232b, DA23, U2, N17).
class Agreements::CreditCoverTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
  end

  teardown { travel_back }

  def effectuated(policies = {})
    @alfa.setting.update!(agreement_policies: policies) if policies.any?
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    @agreement.reload
  end

  def pay_on(day, number, cents)
    travel_day(day)
    pay_lines([ pay_line(number, day, cents) ])
  end

  def add_credit(cents, on)
    Credit.create!(tenant: @alfa, contract: @nf1.contract, kind: :entry, amount_cents: cents, reason: :excess, occurred_at: on.in_time_zone.change(hour: 10))
  end

  def run_daily(day)
    travel_day(day)
    Agreements::Daily.new(@alfa).apply(today: day)
    @agreement.reload
  end

  def title(number) = Bill.find_by!(number: number).reload

  test "N17, padrão 'suspende a quebra': o crédito que cobre o atraso evita a quebra e congela os encargos; quando deixa de cobrir, os dias de quebra contam desse dia" do
    effectuated
    add_credit(70_000, Date.new(2026, 12, 20))
    run_daily(Date.new(2027, 1, 10)) # a parcela 1 venceu em 07/12: 34 dias
    assert_includes %w[active_on_time active_late], @agreement.state
    assert_not_predicate @agreement, :state_broken?
    assert_equal [ "credit" ], @agreement.frozen_spans.map { |span| span["kind"] }
    assert_nil @agreement.frozen_spans.first["to"]

    Credit.create!(tenant: @alfa, contract: @nf1.contract, kind: :transfer_out, amount_cents: -70_000, reason: :transfer, occurred_at: Time.zone.parse("2027-01-12 10:00"))
    run_daily(Date.new(2027, 1, 12))
    assert_equal "2027-01-12", @agreement.frozen_spans.first["to"]
    assert_not_predicate @agreement, :state_broken?, "os dias de quebra contam de 12/01"
    run_daily(Date.new(2027, 2, 12))
    assert_predicate @agreement, :state_broken?, "30 dias depois de 12/01 e o dia seguinte ao fim do prazo"
  end

  test "N17: os encargos de atraso do período congelado não voltam" do
    effectuated
    add_credit(70_000, Date.new(2026, 12, 20))
    run_daily(Date.new(2027, 1, 10))
    Credit.create!(tenant: @alfa, contract: @nf1.contract, kind: :transfer_out, amount_cents: -70_000, reason: :transfer, occurred_at: Time.zone.parse("2027-01-20 10:00"))
    run_daily(Date.new(2027, 1, 20))
    ledger = Agreements::LedgerLoader.new(@alfa, today: Date.new(2027, 1, 30)).one(title("ACD-000001-01"))
    # 07/12 a 30/01 = 54 dias; congelado de 10/01 a 20/01 (10 dias) não corre: os juros contam 44 dias.
    full = Agreements::LedgerLoader.new(@alfa, today: Date.new(2027, 1, 30)).one(title("ACD-000001-01").tap { |bill| bill.composition = bill.composition }).late_breakdown(Date.new(2027, 1, 30))
    assert_operator ledger.late_owed(Date.new(2027, 1, 30)), :<=, full.values.sum
    assert_operator ledger.late_breakdown(Date.new(2027, 1, 30)).fetch("interest"), :>, 0
  end

  test "DA23, 'aplica antes de quebrar': o crédito paga a parcela vencida com a data mais tardia entre o vencimento e o dia em que ficou disponível" do
    effectuated("credit_and_break" => "before_break")
    add_credit(40_000, Date.new(2026, 11, 20)) # já existia no vencimento da parcela 1 (07/12): paga em dia, sem encargos
    run_daily(Date.new(2026, 12, 20))

    bill = title("ACD-000001-01")
    assert_predicate bill, :paid?
    assert_equal Date.new(2026, 12, 7), bill.paid_on
    assert_equal 40_000 - 31_253, @nf1.contract.credit_cents
    assert_equal 0, Agreements::LedgerLoader.new(@alfa, today: Date.new(2026, 12, 20)).one(bill).late_owed(Date.new(2026, 12, 20))
  end

  test "DA23, 'aplica antes de quebrar': o crédito que ficou disponível depois do vencimento paga com encargos até esse dia" do
    effectuated("credit_and_break" => "before_break")
    add_credit(40_000, Date.new(2026, 12, 17))
    run_daily(Date.new(2026, 12, 20))

    bill = title("ACD-000001-01")
    assert_equal Date.new(2026, 12, 17), bill.paid_on
    assert_predicate bill, :paid?
    assert_operator 40_000 - @nf1.contract.credit_cents, :>, 31_253, "pagou também os encargos de dez dias de atraso"
  end

  test "DA23, 'aplica depois da quebra': o acordo quebra e o crédito abate os títulos em cobrança" do
    effectuated("credit_and_break" => "after_break")
    run_daily(Date.new(2027, 1, 20)) # sem crédito ainda: quebra (parcela 1 venceu em 07/12, mais de 30 dias)
    assert_predicate @agreement, :state_broken?
    add_credit(10_000, Date.new(2027, 1, 21))
    run_daily(Date.new(2027, 1, 22))

    assert_operator title("ACD-000001-01").paid_cents, :>, 0
    assert_equal 0, @nf1.contract.credit_cents
  end

  test "U2: na efetivação pelo aceite, a entrada vencida além da tolerância recebe o crédito disponível, mesmo que só cubra parte, e o acordo quebra só pelo resto" do
    @alfa.setting.update!(agreement_policies: { "effectuation" => "acceptance" })
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    assert_predicate @agreement.reload, :state_active_on_time?
    add_credit(20_000, Date.new(2026, 11, 1))
    run_daily(Date.new(2026, 11, 10)) # entrada de 05/11, tolerância até 08/11 (domingo) -> 09/11

    entry = title("ACD-000001-00")
    assert_equal 20_000, entry.paid_cents
    assert_predicate @agreement, :state_broken?, "o resto da entrada passa do mínimo (zero)"
  end

  test "U2, 'aviso ao gestor': o crédito não paga a entrada" do
    @alfa.setting.update!(agreement_policies: { "effectuation" => "acceptance", "credit_and_late_down_payment" => "notice" })
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    add_credit(20_000, Date.new(2026, 11, 1))
    run_daily(Date.new(2026, 11, 10))

    assert_equal 0, title("ACD-000001-00").paid_cents
  end

  test "Z9: o crédito de C-3 não é usado em acordo de outro contrato" do
    effectuated("credit_and_break" => "before_break")
    other = make_bill(@alfa, number: "OUTRO", contract_code: "CT-3", document: PaymentsHelper::MARIA, name: "Maria Souza").contract
    Credit.create!(tenant: @alfa, contract: other, kind: :entry, amount_cents: 40_000, reason: :excess, occurred_at: Time.zone.parse("2026-11-20 10:00"))
    run_daily(Date.new(2026, 12, 20))

    assert_predicate title("ACD-000001-01"), :active?
    assert_equal 40_000, other.credit_cents
  end
end
