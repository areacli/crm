require "test_helper"

# Crédito do contrato no acordo (11, R223, R223a): oferta pelas políticas, uso como pagamento da entrada ou abatimento, consumo no aceite e devolução.
class Agreements::CreditUseTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2 = agreement_scenario(@alfa)
    make_channel(@alfa)
    @contract = @nf1.contract
    add_credit(@contract, 4_366)
  end

  teardown { travel_back }

  def add_credit(contract, cents, at: 3.days.ago) = Credit.create!(tenant: contract.tenant, contract: contract, kind: :entry, amount_cents: cents, reason: :excess, occurred_at: at)

  test "R223: o crédito de R$ 43,66 usado como pagamento da entrada deixa R$ 300,00 a pagar dos R$ 343,66" do
    agreement = create_proposal(@customer, [ @nf1, @nf2 ], credit: 4_366)
    assert_equal [ "down_payment", 4_366, 0 ], [ agreement.credit_mode, agreement.credit_down_cents, agreement.credit_cents ]

    accept_proposal(agreement, @customer)
    entry = Bill.find_by!(number: "ACD-000001-00")

    assert_equal 4_366, entry.reload.paid_cents
    assert_equal 0, @contract.credit_cents, "o crédito foi consumido no aceite"
    assert_predicate agreement.reload, :state_awaiting_effectuation?
    assert_equal 30_000, Agreements::LedgerLoader.new(@alfa, today: AGREEMENT_DAY).one(entry).due(AGREEMENT_DAY).total
    assert_equal "CRM-CREDITO", Payment.find_by!(agreement_id: agreement.id).channel.code
  end

  test "R223: o crédito que cobre a entrada inteira efetiva o acordo no aceite" do
    add_credit(@contract, 30_000)
    agreement = create_proposal(@customer, [ @nf1, @nf2 ], credit: 34_366)
    accept_proposal(agreement, @customer)

    assert_predicate agreement.reload, :state_active_on_time?
    assert_equal "credit", agreement.effectuated_by
  end

  test "R223: como abatimento do valor do acordo, o crédito reduz o valor líquido e a composição dos títulos, depois dos descontos" do
    @alfa.setting.update!(agreement_policies: { "credit_entry" => "rebate" })
    quote = simulate_agreement(@customer, [ @nf1, @nf2 ], credit: 4_366, down: 30_000)

    assert_nil quote.error
    assert_equal [ 154_366, 150_000 ], [ quote.value_cents, quote.net_cents ]
    assert_equal 4_366, quote.rows.sum(&:credit_total)
    assert_equal({ "interest" => 1_751, "fine" => 1_005, "correction" => 534, "principal" => 1_076 }, quote.rows.first.credit)
    assert_equal 150_000, quote.rows.sum(&:value)
  end

  test "R223, Z8: o crédito que cobre o valor do acordo inteiro entra como pagamento da entrada de um acordo à vista, e o acordo fica quitado" do
    @alfa.setting.update!(agreement_policies: { "credit_entry" => "rebate" })
    add_credit(@contract, 150_000)
    agreement = create_proposal(@customer, [ @nf1, @nf2 ], credit: 154_366, discounts: { "fine" => 5_000, "interest" => 5_000 })
    accept_proposal(agreement, @customer)

    assert_equal "cash", agreement.reload.mode
    assert_predicate agreement, :state_settled?
  end

  test "R223a: no padrão só o crédito dos contratos dos títulos é oferecido, e cada um cobre títulos do próprio contrato; com a soma ligada, a distribuição segue a ordem" do
    other = Contract.create!(tenant: @alfa, code: "CT-2")
    ContractCustomer.create!(contract: other, customer: @customer)
    add_credit(other, 5_000)
    bill = Bill.create!(tenant: @alfa, contract: other, customer: @customer, number: "NF-3", due_date: Date.new(2026, 9, 1), amount_cents: 20_000)

    assert_match(/permite usar até R\$ 43,66/, simulate_agreement(@customer, [ @nf1, @nf2 ], credit: 4_400).error, "o crédito do CT-2 não é de nenhum título do acordo")
    assert_match(/permite usar até R\$ 93,66/, simulate_agreement(@customer, [ @nf1, @nf2, bill ], credit: 9_400).error)

    @alfa.setting.update!(agreement_policies: { "credit_across_contracts" => "sum" })
    ok = simulate_agreement(@customer, [ @nf1, @nf2, bill ], credit: 9_000)
    assert_nil ok.error
    assert_equal({ @contract.id => 4_366, other.id => 4_634 }, ok.credit.distribution.to_h)
  end

  test "R223: o crédito pedido não passa do disponível nem, como entrada, da entrada" do
    assert_match(/permite usar até R\$ 43,66/, simulate_agreement(@customer, [ @nf1, @nf2 ], credit: 5_000).error)
    add_credit(@contract, 50_000)
    assert_match(/não passa da entrada/, simulate_agreement(@customer, [ @nf1, @nf2 ], credit: 40_000).error)
  end

  test "R220: o crédito usado que deixou de estar disponível recusa o aceite" do
    agreement = create_proposal(@customer, [ @nf1, @nf2 ], credit: 4_366)
    Credit.create!(tenant: @alfa, contract: @contract, kind: :transfer_out, amount_cents: -4_366, reason: :transfer)

    assert_equal I18n.t("agreements.accept_refused.credit_unavailable"), refuse_agreement { accept_proposal(agreement, @customer) }
  end

  test "R223, R235: o acordo cancelado antes da efetivação devolve o crédito ao contrato e estorna o pagamento da entrada" do
    agreement = create_proposal(@customer, [ @nf1, @nf2 ], credit: 4_366)
    accept_proposal(agreement, @customer)
    Agreements::Release.new(users(:joana)).call(agreement.reload, to: "canceled", reason: "cliente desistiu", event: "canceled")

    assert_equal 4_366, @contract.credit_cents
    assert_equal 0, Bill.find_by!(number: "ACD-000001-00").paid_cents
    assert_equal Payment.find_by!(agreement_id: agreement.id).amount_cents, Payment.find_by!(agreement_id: agreement.id).reversed_cents
  end
end
