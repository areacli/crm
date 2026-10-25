require "test_helper"

# Estornos bancários sobre acordos e crédito (11, R233 e a tabela de estornos, R62): regra base com o prazo novo (N10), espera do gestor, título de estorno (U1, AF3), crédito
# transferido e o teste da soma do acordo encerrado.
class Agreements::ReversalEffectsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @gestor = users(:joana)
    travel_day(AGREEMENT_DAY)
  end

  teardown { travel_back }

  def title(number) = Bill.find_by!(number: number).reload

  def pay(day, number, cents, id)
    travel_day(day)
    pay_lines([ pay_line(number, day, cents, id: id) ])
  end

  def reverse(day, id, cents)
    travel_day(day)
    run_payments_import([ reversal_line("identificador_pagamento" => id, "valor" => Money.format(cents), "data_estorno" => day.strftime("%d/%m/%Y"), "identificador_estorno" => "E-#{SecureRandom.hex(3)}") ],
                        kind: "reversals", confirm: true)
  end

  # Acordo efetivado pela entrada de 04/11; devolve o acordo.
  def effectuated
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    pay(Date.new(2026, 11, 4), "ACD-000001-00", 34_366, "PIX-ENTRADA")
    @agreement.reload
  end

  test "N10, regra base: o estorno do pagamento da parcela 1 reabre a parcela e os dias de quebra contam do estorno (prazo novo)" do
    effectuated
    pay(Date.new(2026, 12, 7), "ACD-000001-01", 31_253, "PIX-P1")
    assert_predicate title("ACD-000001-01"), :paid?
    reverse(Date.new(2026, 12, 10), "PIX-P1", 31_253)

    bill = title("ACD-000001-01")
    assert_predicate bill, :active?
    assert_equal 0, bill.paid_cents
    assert_equal "2026-12-10", bill.composition["reopened_on"]
    travel_day(Date.new(2027, 1, 5))
    assert_nil Agreements::Breaker.cause(@agreement.reload, Date.new(2027, 1, 5)), "venceu em 07/12, mas os 30 dias contam de 10/12"
    assert_equal "installment", Agreements::Breaker.cause(@agreement, Date.new(2027, 1, 12))
  end

  test "N10, alternativa 'atraso desde o vencimento': a parcela reaberta quebra pelos dias contados do vencimento" do
    @alfa.setting.update!(agreement_policies: { "bank_reversal" => "since_due" })
    effectuated
    pay(Date.new(2026, 12, 7), "ACD-000001-01", 31_253, "PIX-P1")
    reverse(Date.new(2026, 12, 10), "PIX-P1", 31_253)

    assert_nil title("ACD-000001-01").composition["reopened_on"]
    assert_equal "installment", Agreements::Breaker.cause(@agreement.reload, Date.new(2027, 1, 7))
  end

  test "R233: estorno de pagamento de acordo em reversão fica à espera do gestor, o título não muda e o gestor decide lançar no crédito" do
    effectuated
    Agreements::Reversion.new(@gestor).open!(@agreement, "teste")
    pay(Date.new(2026, 11, 20), "ACD-000001-01", 5_000, "PIX-P1")
    reverse(Date.new(2026, 11, 25), "PIX-P1", 5_000)

    wait = ReversalWait.sole
    assert_predicate wait, :state_waiting?
    assert_equal "in_reversion", wait.reason
    assert_equal 5_000, wait.amount_cents
    assert_equal 0, Credit.available.where(contract_id: @nf1.contract_id).sum(:amount_cents), "o crédito do pagamento estornado fica bloqueado (AK2)"
    assert_equal 5_000, @nf1.contract.credit_balances["blocked"], "o crédito do pagamento estornado fica bloqueado (AK2)"

    decision = Agreements::WaitDecision.new(@gestor)
    assert_not_includes decision.options(wait), "reopen"
    assert_includes decision.options(wait), "credit"
    assert_raises(Agreements::Refused) { decision.decide!(wait, "credit", " ") }
    decision.decide!(wait, "credit", "devolvido pelo banco")

    assert_predicate wait.reload, :state_decided?
    assert_equal "credit", wait.decision
    assert_equal 0, @nf1.contract.credit_balances["blocked"]
    assert_equal 0, @nf1.contract.credit_cents, "o lançamento do gestor e o crédito desbloqueado se compensam"
    assert_equal 34_366, @nf1.contract.credit_balances["awaiting"]
  end

  test "AF3: o pagamento anterior à montagem, estornado depois da efetivação, gera o título de estorno com os descontos do acordo, fora do acordo" do
    customer, nf1, nf2 = agreement_scenario(@alfa)
    make_channel(@alfa)
    travel_day(Date.new(2026, 10, 1))
    pay_lines([ pay_line("NF-2", Date.new(2026, 10, 1), 10_000, id: "PIX-ANTES") ])
    travel_day(AGREEMENT_DAY)
    agreement = create_proposal(customer, [ nf1.reload, nf2.reload ])
    accept_proposal(agreement, customer)
    pay(Date.new(2026, 11, 4), "ACD-000001-00", agreement.reload.down_payment_cents, "PIX-ENTRADA")
    assert_equal "renegotiated", nf2.reload.status

    reverse(Date.new(2026, 11, 20), "PIX-ANTES", 10_000)

    extra = Bill.find_by!(number: "ACD-000001-E1")
    assert_predicate extra, :kind_reversal?
    assert_equal agreement.id, extra.origin_agreement_id
    assert_nil extra.agreement_id
    assert_equal "renegotiated", nf2.reload.status, "o original renegociado não volta à cobrança"
    assert_operator extra.amount_cents, :>, 9_000, "o que o estorno tirou, com os descontos do acordo na multa e nos juros, mais os encargos até a montagem"
    assert_equal 0, agreement.reload.titles.count { |bill| bill.number.include?("E") }
    assert_equal Date.new(2026, 11, 30), extra.due_date, "20/11 mais o prazo da entrada de 10 dias, em dia útil"
  end

  test "U1: o estorno da origem do crédito usado como abatimento, depois da efetivação, gera o título de estorno com a composição que o crédito cobriu" do
    @alfa.setting.update!(agreement_policies: { "credit_entry" => "rebate" })
    @customer, @nf1, @nf2 = agreement_scenario(@alfa)
    make_channel(@alfa)
    pago = make_bill(@alfa, number: "NF-0", contract_code: "CT-1", amount_cents: 10_000, status: :paid, document: PaymentsHelper::MARIA)
    pago.update_columns(paid_cents: 10_000)
    travel_day(Date.new(2026, 10, 20))
    pay_lines([ pay_line("NF-0", Date.new(2026, 10, 20), 4_366, id: "PIX-CREDITO") ])
    travel_day(AGREEMENT_DAY)
    agreement = create_proposal(@customer, [ @nf1.reload, @nf2.reload ], credit: 4_366)
    assert_equal 4_366, agreement.credit_cents
    accept_proposal(agreement, @customer)
    pay(Date.new(2026, 11, 4), "ACD-000001-00", agreement.reload.down_payment_cents, "PIX-ENTRADA")
    assert_equal 0, @nf1.contract.credit_cents

    reverse(Date.new(2026, 11, 20), "PIX-CREDITO", 4_366)

    extra = Bill.find_by!(number: "ACD-000001-E1")
    assert_equal 4_366, extra.amount_cents
    assert_equal [ [ "interest", 1_751 ], [ "fine", 1_005 ], [ "correction", 534 ], [ "principal", 1_076 ] ], extra.composition["items"].map { |item| [ item["component"], item["cents"] ] }
    assert_predicate agreement.reload, :state_active_on_time?, "o acordo não muda (R233)"
    assert_equal 4_366, extra.composition["credit_origin"]
  end

  test "V1: o estorno da origem do crédito usado como abatimento cancela o acordo que ainda aguarda a efetivação" do
    @alfa.setting.update!(agreement_policies: { "credit_entry" => "rebate" })
    @customer, @nf1, @nf2 = agreement_scenario(@alfa)
    make_channel(@alfa)
    pago = make_bill(@alfa, number: "NF-0", contract_code: "CT-1", amount_cents: 10_000, status: :paid, document: PaymentsHelper::MARIA)
    pago.update_columns(paid_cents: 10_000)
    travel_day(Date.new(2026, 10, 20))
    pay_lines([ pay_line("NF-0", Date.new(2026, 10, 20), 4_366, id: "PIX-CREDITO") ])
    travel_day(AGREEMENT_DAY)
    agreement = create_proposal(@customer, [ @nf1.reload, @nf2.reload ], credit: 4_366)
    accept_proposal(agreement, @customer)
    reverse(Date.new(2026, 11, 2), "PIX-CREDITO", 4_366)

    assert_predicate agreement.reload, :state_canceled?
    assert_equal "crédito estornado: monte a proposta de novo", agreement.reason
  end

  test "R62: o estorno do pagamento cujo crédito foi transferido sai do contrato de quem recebeu, sem título de estorno" do
    pago = make_bill(@alfa, number: "NF-0", contract_code: "CT-A", amount_cents: 10_000, status: :paid, document: PaymentsHelper::MARIA)
    pago.update_columns(paid_cents: 10_000)
    make_channel(@alfa)
    other = make_bill(@alfa, number: "OUTRO", contract_code: "CT-B", document: PaymentsHelper::JOAO, name: "João").contract
    travel_day(Date.new(2026, 10, 20))
    pay_lines([ pay_line("NF-0", Date.new(2026, 10, 20), 20_000, id: "PIX-CRED") ])
    assert_equal 20_000, pago.contract.credit_cents
    Payments::CreditTransfer.new(@gestor).transfer(from: pago.contract, to: other, cents: 20_000, reason: "contrato certo")
    reverse(Date.new(2026, 10, 25), "PIX-CRED", 20_000)

    assert_equal 0, other.credit_cents
    assert_equal 0, pago.contract.credit_cents
    assert_equal 0, Bill.where(kind: "reversal").count
  end

  test "AE3, AF1: o acordo quitado continua quitado quando o estorno reabre resto igual ou abaixo do mínimo, e reabre quando passa dele" do
    @alfa.setting.update!(agreement_policies: { "minimum_to_break" => { "kind" => "cents", "value" => 1_000 } })
    effectuated
    @agreement.update!(terms: @agreement.terms.deep_merge("policies" => { "minimum_to_break" => { "kind" => "cents", "value" => 1_000 } }))
    pay(Date.new(2026, 12, 7), "ACD-000001-01", 31_253, "PIX-P1")
    pay(Date.new(2027, 1, 5), "ACD-000001-02", 31_133, "PIX-P2")
    pay(Date.new(2027, 2, 5), "ACD-000001-03", 31_133, "PIX-P3")
    pay(Date.new(2027, 3, 5), "ACD-000001-04", 31_134, "PIX-P4")
    assert_predicate @agreement.reload, :state_settled?

    reverse(Date.new(2027, 3, 20), "PIX-P4", 300)
    assert_predicate @agreement.reload, :state_settled?, "R$ 3,00 ficam abaixo do mínimo de R$ 10,00"
    assert_equal 300, Abatement.where(kind: "minimum", bill_id: title("ACD-000001-04").id).sum(:amount_cents)

    reverse(Date.new(2027, 3, 21), "PIX-P4", 2_000)
    assert_predicate @agreement.reload, :state_active_on_time?, "acima do mínimo o acordo reabre"
    assert_equal 0, Abatement.where(kind: "minimum", bill_id: title("ACD-000001-04").id).sum(:amount_cents)
  end

  test "R240, AF3: o estorno de pagamento feito antes da montagem cancela o acordo que ainda aguarda a efetivação, com 'valor do título mudou'" do
    customer, nf1, nf2 = agreement_scenario(@alfa)
    make_channel(@alfa)
    travel_day(Date.new(2026, 10, 1))
    pay_lines([ pay_line("NF-2", Date.new(2026, 10, 1), 10_000, id: "PIX-ANTES") ])
    travel_day(AGREEMENT_DAY)
    agreement = create_proposal(customer, [ nf1.reload, nf2.reload ])
    accept_proposal(agreement, customer)
    reverse(Date.new(2026, 11, 2), "PIX-ANTES", 10_000)

    assert_predicate agreement.reload, :state_canceled?
    assert_equal "valor do título mudou", agreement.reason
    assert_predicate nf2.reload, :active?
    assert_equal 0, nf2.paid_cents
  end
end
