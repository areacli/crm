require "test_helper"

# Títulos do acordo, efetivação e pagamento pelo número (11, R221 a R232b), com os números da especificação ao centavo.
class Agreements::PaymentFlowTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    travel_day(AGREEMENT_DAY)
    @customer, @nf1, @nf2, @agreement = accepted_agreement(@alfa)
    @entry = Bill.find_by!(number: "ACD-000001-00")
  end

  teardown { travel_back }

  def pay_on(day, number, cents, **options)
    travel_day(day)
    pay_lines([ pay_line(number, day, cents, **options) ])
  end

  def title(number) = Bill.find_by!(number: number).reload

  test "R221, R224: o aceite cria a entrada e as quatro parcelas como títulos da carteira, a vencer, com a composição dos originais" do
    assert_equal %w[ACD-000001-00 ACD-000001-01 ACD-000001-02 ACD-000001-03 ACD-000001-04], @agreement.titles.map(&:number)
    assert_equal [ "scheduled" ], @agreement.titles.map(&:status).uniq
    assert_equal [ 34_366, 31_253, 31_133, 31_133, 31_134 ], @agreement.titles.map(&:amount_cents)
    assert_equal [ @nf1.contract_id ], @agreement.titles.map(&:contract_id).uniq

    items = @entry.composition["items"].map { |item| [ item["component"], item["cents"] ] }
    assert_equal [ [ "interest", 1_751 ], [ "fine", 1_005 ], [ "correction", 534 ], [ "principal", 31_076 ] ], items
    parcel3 = title("ACD-000001-03").composition["items"].map { |item| [ item["bill_id"] == @nf1.id ? "NF-1" : "NF-2", item["component"], item["cents"] ] }
    assert_equal [ [ "NF-1", "principal", 9_818 ], [ "NF-2", "interest", 369 ], [ "NF-2", "fine", 502 ], [ "NF-2", "correction", 205 ], [ "NF-2", "principal", 19_326 ] ], parcel3
    assert_equal 1_360, title("ACD-000001-02").composition["installment_interest"]
    assert_equal 32, title("ACD-000001-01").composition["period_days"]
    assert_predicate @nf1.reload, :active?, "os originais seguem em cobrança até a efetivação (R221)"
  end

  test "R225: pagar a entrada de R$ 343,66 em 04/11 efetiva o acordo: originais renegociados, parcelas a cobrar e o acordo ativo em dia" do
    import = pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)

    assert_predicate import, :confirmed?
    assert_predicate @agreement.reload, :state_active_on_time?
    assert_equal "payment", @agreement.effectuated_by
    assert_equal [ "renegotiated" ], [ @nf1.reload.status, @nf2.reload.status ].uniq
    assert_equal %w[paid active active active active], @agreement.titles.map(&:status)
    assert_equal %w[built accepted effectuated], @agreement.events.order(:id).map(&:kind)
    assert_equal 120_000 + 4_653 - 0, @agreement.titles.where(status: "active").sum { |bill| bill.amount_cents - bill.paid_cents }
  end

  test "R225, AB2: o pagamento com o número de uma parcela, ou do acordo sem sufixo, antes da efetivação vai primeiro à entrada" do
    pay_on(Date.new(2026, 11, 3), "ACD-000001-02", 20_000)

    assert_equal 20_000, @entry.reload.paid_cents
    assert_predicate @agreement.reload, :state_awaiting_effectuation?
    pay_on(Date.new(2026, 11, 4), "ACD-000001", 14_366)
    assert_predicate @agreement.reload, :state_active_on_time?
    assert_predicate @entry.reload, :paid?
  end

  test "R227: o excedente do pagamento da entrada vira crédito do contrato (DA9, padrão)" do
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 40_000)

    assert_equal 40_000 - 34_366, @nf1.contract.credit_cents
    assert_predicate @agreement.reload, :state_active_on_time?
  end

  test "DA9, alternativa: o excedente abate os títulos de acordo seguintes" do
    @alfa.setting.update!(agreement_policies: { "overpayment" => "rebate_next" })
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366 + 5_000)

    assert_equal 0, @nf1.contract.credit_cents
    assert_equal 5_000 - 0, title("ACD-000001-01").paid_cents.then { |paid| paid }.clamp(0, 5_000)
  end

  test "R234: a entrada paga com quatro dias de atraso só efetiva com a mora: R$ 343,66 não bastam, R$ 350,40 sim (multa R$ 6,32 e juros R$ 0,42)" do
    pay_on(Date.new(2026, 11, 9), "ACD-000001-00", 34_366)
    assert_predicate @agreement.reload, :state_awaiting_effectuation?, "o pagamento sem a mora deixa a entrada em aberto"
    assert_equal 674, Agreements::LedgerLoader.new(@alfa, today: Date.current).one(@entry.reload).due(Date.new(2026, 11, 9)).total

    pay_on(Date.new(2026, 11, 9), "ACD-000001-00", 674)
    assert_predicate @agreement.reload, :state_active_on_time?
    assert_equal 35_040, Payment.where(bill_id: @entry.id).sum(:amount_cents)
  end

  test "N6: com a política 'só gera crédito', a entrada paga depois do vencimento não efetiva e vira crédito do contrato" do
    @agreement.update!(terms: @agreement.terms.deep_merge("policies" => { "late_down_payment" => "credit_only" }))
    pay_on(Date.new(2026, 11, 9), "ACD-000001-00", 35_040)

    assert_predicate @agreement.reload, :state_awaiting_effectuation?
    assert_equal 35_040, @nf1.contract.credit_cents
  end

  test "R228: a parcela 2 paga em 20/01/2027 custa R$ 318,77 com a mora; paga, o título fica pago e o acordo em dia" do
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    pay_on(Date.new(2027, 1, 20), "ACD-000001-02", 31_877)
    bill = title("ACD-000001-02")

    assert_predicate bill, :paid?
    assert_equal 31_133, bill.paid_cents
    assert_equal({ "late" => 744, "installment_interest" => 1_360, "principal" => 29_773 }, PaymentAllocation.where(bill_id: bill.id).group(:component).sum(:amount_cents))
  end

  test "R228a: o boleto de R$ 318,70 na parcela 2 deixa o título pago com R$ 0,07 de abatimento por tolerância" do
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    pay_on(Date.new(2027, 1, 20), "ACD-000001-02", 31_870)

    assert_predicate title("ACD-000001-02"), :paid?
    assert_equal [ [ "tolerance", "principal", 7 ] ], Abatement.where(bill_id: title("ACD-000001-02").id).pluck(:kind, :component, :amount_cents)
  end

  test "R226, N1: o estado final 'quitado' dá a parcela por paga, com o abatimento do credor" do
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    pay_on(Date.new(2027, 1, 5), "ACD-000001-02", 20_000, estado_final: "quitado")

    assert_predicate title("ACD-000001-02"), :paid?
    assert_equal 11_133, Abatement.where(bill_id: title("ACD-000001-02").id, kind: "creditor").sum(:amount_cents)
  end

  test "R229: com mínimo de R$ 10,00 a parcela 2 paga pelo valor de face 15 dias depois fica com R$ 7,44 em aberto, e o acordo segue ativo" do
    @agreement.update!(terms: @agreement.terms.deep_merge("policies" => { "minimum_to_break" => { "kind" => "cents", "value" => 1_000 } }))
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    pay_on(Date.new(2027, 1, 20), "ACD-000001-02", 31_133)
    bill = title("ACD-000001-02")

    assert_predicate bill, :active?
    assert_equal 744, Agreements::LedgerLoader.new(@alfa, today: Date.new(2027, 1, 20)).one(bill).principal_remaining
  end

  test "R229: o resto igual ou abaixo do mínimo, quando todos os outros títulos estão pagos, quita o acordo com abatimento por mínimo" do
    @agreement.update!(terms: @agreement.terms.deep_merge("policies" => { "minimum_to_break" => { "kind" => "cents", "value" => 1_000 } }))
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    pay_on(Date.new(2026, 12, 7), "ACD-000001-01", 31_253)
    pay_on(Date.new(2027, 1, 5), "ACD-000001-02", 31_133)
    pay_on(Date.new(2027, 2, 5), "ACD-000001-03", 31_133)
    pay_on(Date.new(2027, 3, 5), "ACD-000001-04", 31_134 - 700)

    assert_predicate @agreement.reload, :state_settled?
    assert_equal 700, Abatement.where(kind: "minimum").sum(:amount_cents)
    assert_predicate title("ACD-000001-04"), :paid?
  end

  test "R230: com o cálculo de quitação de 04/01, o pagamento do valor calculado com o número do acordo quita tudo e dispensa os juros futuros" do
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    pay_on(Date.new(2026, 12, 7), "ACD-000001-01", 31_253)
    travel_day(Date.new(2026, 12, 20))
    quote = AgreementSettlement.calculate!(@agreement.reload, on: Date.new(2026, 12, 31), user: users(:carlos))
    assert_operator quote.amount_cents, :<, 31_133 * 3 + 1
    pay_on(Date.new(2026, 12, 28), "ACD-000001", quote.amount_cents)

    assert_predicate @agreement.reload, :state_settled?
    assert_equal [ "paid" ], @agreement.titles.map(&:status).uniq - [ "paid" ] + [ "paid" ]
    assert_empty @agreement.titles.where.not(status: "paid")
  end

  test "R232, DA7: o pagamento direto de um título original antes da efetivação vai para o título e cancela o acordo, com a entrada parcial alocada nos originais" do
    pay_on(Date.new(2026, 11, 3), "ACD-000001-00", 10_000)
    pay_on(Date.new(2026, 11, 4), "NF-2", 52_100)

    assert_predicate @agreement.reload, :state_canceled?
    assert_equal "título pago fora do acordo", @agreement.reason
    assert_equal [ "canceled" ], @agreement.titles.map(&:status).uniq
    assert_predicate @nf2.reload, :paid?
    assert_equal 0, AgreementBill.where(agreement: @agreement, held: true).count
    assert_operator @nf1.reload.paid_cents, :>, 0, "os R$ 100,00 da entrada foram para os originais"
  end

  test "DA8: o pagamento a título original já renegociado vira crédito do contrato, com o motivo 'título renegociado'" do
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    pay_on(Date.new(2026, 11, 5), "NF-2", 10_000)

    assert_equal 10_000, @nf1.contract.credit_cents
    assert_equal "renegotiated", Credit.order(:id).last.reason
  end

  test "R232a: a entrada e o boleto do NF-2 no mesmo arquivo e na mesma data: a entrada efetiva primeiro e o boleto segue a DA8" do
    travel_day(Date.new(2026, 11, 4))
    pay_lines([ pay_line("NF-2", Date.new(2026, 11, 4), 10_000, id: "A"), pay_line("ACD-000001-00", Date.new(2026, 11, 4), 34_366, id: "B") ])

    assert_predicate @agreement.reload, :state_active_on_time?
    assert_equal 10_000, @nf1.contract.credit_cents
  end

  test "R231: o pagamento a título de acordo já pago é excedente, pela DA9" do
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    pay_on(Date.new(2026, 11, 5), "ACD-000001-00", 5_000)

    assert_equal 5_000, @nf1.contract.credit_cents
  end

  test "V10: o pagamento com o número de acordo de outro credor não toca o acordo" do
    beta = tenants(:beta)
    make_channel(beta)
    make_bill(beta, number: "NB-1", document: PaymentsHelper::JOAO, contract_code: "CB-1", name: "João")
    travel_day(Date.new(2026, 11, 4))
    run_payments_import([ pay_line("ACD-000001-00", Date.new(2026, 11, 4), 34_366, documento: PaymentsHelper::JOAO) ], tenant: beta, confirm: true)

    assert_predicate @agreement.reload, :state_awaiting_effectuation?
    assert_equal 0, @entry.reload.paid_cents
  end

  test "R225: a política 'efetivação pelo aceite' efetiva no aceite: a entrada já é título vigente" do
    @agreement.update!(state: "canceled")
    @agreement.agreement_bills.update_all(held: false)
    @alfa.setting.update!(agreement_policies: { "effectuation" => "acceptance" })
    second = create_proposal(@customer, [ @nf1, @nf2 ])
    accept_proposal(second, @customer)

    assert_predicate second.reload, :state_active_on_time?
    assert_equal "acceptance", second.effectuated_by
    assert_equal [ "renegotiated" ], [ @nf1.reload.status, @nf2.reload.status ].uniq
    assert_equal [ "active" ], second.titles.map(&:status).uniq
  end

  test "R222: o aceite cancela as promessas abertas dos títulos, sem carência" do
    @agreement.update!(state: "canceled")
    @agreement.agreement_bills.update_all(held: false)
    PaymentPromise.delete_all
    promise = register_promise(@customer, [ @nf1 ])
    second = create_proposal(@customer, [ @nf1, @nf2 ])
    assert_predicate promise.reload, :state_open?
    accept_proposal(second, @customer)

    assert_predicate promise.reload, :state_canceled?
    assert_equal "títulos renegociados em acordo", promise.reason
    assert promise.grace_free
  end

  test "R240: título original retirado numa carga cancela o acordo aguardando efetivação" do
    @nf2.update!(status: "withdrawn")
    Agreements::BillExit.run(@alfa.id)

    assert_predicate @agreement.reload, :state_canceled?
    assert_equal "título fora da cobrança", @agreement.reason
  end

  test "R240: valor vigente do original mudado cancela o acordo" do
    @nf1.update!(amount_cents: 110_000)
    Agreements::BillExit.run(@alfa.id)

    assert_equal "valor do título mudou", @agreement.reload.reason
  end

  test "DA8, alternativa: o pagamento a título original renegociado abate o título de acordo mais antigo em aberto" do
    @alfa.setting.update!(agreement_policies: { "renegotiated_payment" => "rebate_oldest" })
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    pay_on(Date.new(2026, 11, 5), "NF-2", 10_000)

    assert_equal 0, @nf1.contract.credit_cents
    allocated = PaymentAllocation.where(bill_id: title("ACD-000001-01").id).group(:component).sum(:amount_cents)
    assert_equal({ "principal" => 10_000 }, allocated, "pago 32 dias antes do vencimento, os juros do parcelamento ainda não correram (DA35)")
  end

  test "DA7, alternativa: o pagamento direto do original vale como pagamento do acordo (primeiro a entrada) e o acordo segue" do
    @agreement.update!(terms: @agreement.terms.deep_merge("policies" => { "original_paid_before" => "counts_as_agreement" }))
    pay_on(Date.new(2026, 11, 4), "NF-2", 34_366)

    assert_predicate @agreement.reload, :state_active_on_time?
    assert_predicate @entry.reload, :paid?
    assert_equal 50_000, @nf2.reload.then { |bill| bill.amount_cents - 0 }
  end

  test "AC11, DA9: o pagamento acima da entrada com o número da parcela efetiva o acordo e o excedente vira crédito do contrato" do
    pay_on(Date.new(2026, 11, 4), "ACD-000001-03", 40_000)

    assert_predicate @agreement.reload, :state_active_on_time?
    assert_equal 5_634, @nf1.contract.credit_cents
  end

  test "R233, regra base: o estorno do pagamento da parcela reabre o título no próprio título e o acordo volta a ativo" do
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    pay_on(Date.new(2026, 12, 7), "ACD-000001-01", 31_253, id: "PIX-P1")
    assert_predicate title("ACD-000001-01"), :paid?

    travel_day(Date.new(2026, 12, 8))
    run_payments_import([ reversal_line("identificador_pagamento" => "PIX-P1", "valor" => "312,53", "data_estorno" => "08/12/2026") ], kind: "reversals", confirm: true)

    bill = title("ACD-000001-01")
    assert_predicate bill, :active?
    assert_equal 0, bill.paid_cents
    assert_equal 0, PaymentAllocation.where(bill_id: bill.id).sum(:amount_cents)
    assert_predicate @agreement.reload, :state_active_on_time?
  end

  test "R230: pagar o valor calculado antes da data do cálculo quita o acordo; na política 'saldo da data do pagamento', o saldo do dia quita" do
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    travel_day(Date.new(2026, 11, 20))
    quote = AgreementSettlement.calculate!(@agreement.reload, on: Date.new(2026, 12, 31))
    pay_on(Date.new(2026, 11, 20), "ACD-000001", quote.amount_cents)

    assert_predicate @agreement.reload, :state_settled?
    assert_empty @agreement.titles.where.not(status: "paid")
    assert_equal 0, @nf1.contract.credit_cents
  end

  test "R229: o resto de título sem nenhum pagamento nunca é perdoado pelo mínimo: o acordo não quita" do
    @agreement.update!(terms: @agreement.terms.deep_merge("policies" => { "minimum_to_break" => { "kind" => "cents", "value" => 99_999 } }))
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    Agreements::Standing.refresh!(@agreement.reload, today: Date.new(2026, 11, 5))

    assert_not_predicate @agreement.reload, :state_settled?
  end

  test "R225: o acordo ativo em dia passa a em atraso quando uma parcela vence há mais que a tolerância e volta a em dia quando é paga" do
    pay_on(Date.new(2026, 11, 4), "ACD-000001-00", 34_366)
    travel_day(Date.new(2026, 12, 10)) # vencimento 07/12 + 3 dias de tolerância = 10/12; em atraso no dia seguinte
    Agreements::Standing.refresh!(@agreement.reload, today: Date.new(2026, 12, 10))
    assert_predicate @agreement.reload, :state_active_on_time?
    Agreements::Standing.refresh!(@agreement, today: Date.new(2026, 12, 11))
    assert_predicate @agreement.reload, :state_active_late?

    pay_on(Date.new(2026, 12, 11), "ACD-000001-01", 33_000)
    assert_predicate @agreement.reload, :state_active_on_time?
  end
end
