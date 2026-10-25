require "test_helper"

# Pagamento de promessa na confirmação (10, R193 a R199, R202, DP1, DP2, DP-T, DP11) e a tarefa diária (R197).
class Promises::PaymentFlowTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    make_channel(@alfa)
    travel_day(TODAY)
    @customer, @nf1, @nf2 = promise_scenario(@alfa)
    @promise = register_promise(@customer, [ @nf1, @nf2 ])
    travel_day(Date.new(2026, 10, 29))
  end

  teardown { travel_back }

  def pay(number, cents, method: "pix", id: "PIX-#{SecureRandom.hex(3)}", days_ago: 0, tenant: @alfa, user: users(:joana))
    line = payment_line("identificador" => id, "titulo" => number, "valor" => Money.format(cents), "meio" => method, "data_pagamento" => brl_date(days_ago))
    run_payments_import([ line ], tenant: tenant, user: user, confirm: true)
  end

  test "R194 a R196: o pagamento da promessa quita os dois títulos, encargos antes do principal, e a promessa fica cumprida" do
    pay("PRM-000001", 157_993)

    assert_equal %w[paid paid], [ @nf1, @nf2 ].map { |bill| bill.reload.status }
    assert_predicate @promise.reload, :state_fulfilled?
    assert_equal 157_993, @promise.paid_cents
    assert_equal 100, @promise.paid_percent
    assert_empty @promise.promise_bills.where(held: true)
    payment = Payment.last
    assert_equal @promise, payment.promise
    assert payment.promise_counted
    assert_nil payment.bill_id
    assert_equal 0, payment.credit_cents
  end

  test "R195 e R197a: R$ 1.065,00 quitam o NF-1 e os R$ 4,53 restantes vão aos juros do NF-2; a promessa continua aberta" do
    pay("PRM-000001", 106_500)

    assert_predicate @nf1.reload, :paid?
    assert_predicate @nf2.reload, :active?
    assert_predicate @promise.reload, :state_open?
    allocations = PaymentAllocation.where(bill: @nf2)
    assert_equal({ "interest" => 453 }, allocations.group(:component).sum(:amount_cents))
  end

  test "R195b e R195c: o título pago antes por boleto fica fora e a diferença vira crédito do contrato" do
    pay("NF-2", 52_000, method: "boleto", id: "BOL-1")
    assert_predicate @nf2.reload, :paid?
    result = pay("PRM-000001", 157_993)

    payment = Payment.find_by(promise: @promise)
    assert_predicate @nf1.reload, :paid?
    assert_predicate @promise.reload, :state_fulfilled?
    assert_equal 106_047, payment.applied_cents
    assert_equal 51_946, payment.credit_cents
    assert_equal 51_946, Credit.where(contract: @nf1.contract, payment: payment).sum(:amount_cents)
    assert_predicate result, :confirmed?
  end

  test "R194: o pagamento por outro meio é pagamento comum dos títulos e não conta para a promessa" do
    pay("PRM-000001", 50_000, method: "boleto")

    payment = Payment.find_by(promise: @promise)
    assert_not payment.promise_counted
    assert_equal 0, @promise.reload.paid_cents
    assert_predicate @promise, :state_open?
    assert_predicate @nf1.reload, :active?
    assert_operator @nf1.paid_cents, :>, 0
  end

  test "R194a: número inexistente fica pendente; número de promessa encerrada vira pagamento comum" do
    pay("PRM-009999", 10_000)
    assert_equal "pending", Payment.last.status

    Promises::Canceller.new(users(:joana)).cancel(@promise, "Pediu para negociar")
    pay("PRM-000001", 10_000, id: "PIX-ENC")
    assert_not Payment.find_by(identifier: "PIX-ENC").promise_counted
    assert_operator @nf1.reload.paid_cents, :>, 0
  end

  test "R196 e revisão 2: títulos liquidados só por pagamentos depois da data prometida deixam a promessa cumprida com atraso" do
    travel_day(Date.new(2026, 11, 1))
    pay("PRM-000001", 160_000, id: "PIX-LATE")

    assert_predicate @promise.reload, :state_fulfilled_late?
    assert_predicate @nf1.reload, :paid?
    assert_equal 0, @promise.paid_cents
  end

  test "revisão 1: títulos liquidados por fora até a data prometida cancelam a promessa" do
    pay("NF-1", 106_100, method: "boleto", id: "B1")
    pay("NF-2", 52_000, method: "boleto", id: "B2")

    assert_predicate @promise.reload, :state_canceled?
    assert_equal "títulos pagos fora da promessa", @promise.reason
  end

  test "R193: a pendente cancelada quando os títulos são pagos direto" do
    Promises::Canceller.new(users(:joana)).cancel(@promise, "Reiniciar")
    travel_day(TODAY)
    Segment.catch_all_of(@alfa).update!(promise_max_days: 60)
    pending = register_promise(@customer, [ @nf1, @nf2 ], user: users(:carlos), on: TODAY + 45)
    travel_day(Date.new(2026, 10, 29))
    pay("NF-1", 106_100, method: "boleto", id: "B1")
    pay("NF-2", 52_000, method: "boleto", id: "B2")

    assert_predicate pending, :state_pending?
    assert_predicate pending.reload, :state_canceled?
    assert_equal "títulos pagos fora da promessa", pending.reason
  end

  test "R197: a tarefa diária quebra a aberta vencida com o percentual pago e libera os títulos" do
    pay("PRM-000001", 20_000)
    travel_day(Date.new(2026, 11, 2))
    Promises::Daily.new(@alfa).apply
    assert_predicate @promise.reload, :state_open?

    travel_day(Date.new(2026, 11, 3))
    assert_equal 1, Promises::Daily.new(@alfa).apply
    assert_predicate @promise.reload, :state_broken?
    assert_equal 13, @promise.paid_percent
    assert_empty @promise.promise_bills.where(held: true)
    assert_predicate register_promise(@customer, [ @nf1 ], on: Date.new(2026, 11, 10)), :state_open?
  end

  test "R193: a pendente sem aprovação no prazo termina como não aprovada" do
    Promises::Canceller.new(users(:joana)).cancel(@promise, "Reiniciar")
    travel_day(TODAY)
    Segment.catch_all_of(@alfa).update!(promise_max_days: 60)
    pending = register_promise(@customer, [ @nf1 ], user: users(:carlos), on: TODAY + 45)
    travel_day(TODAY + 49)
    Promises::Daily.new(@alfa).apply

    assert_predicate pending.reload, :state_not_approved?
    assert_nil pending.number
    assert_empty pending.promise_bills.where(held: true)
  end

  test "R198: pagamento no prazo importado depois da quebra torna a promessa cumprida, ou não, conforme a política" do
    travel_day(Date.new(2026, 11, 3))
    Promises::Daily.new(@alfa).apply
    assert_predicate @promise.reload, :state_broken?
    pay("PRM-000001", 157_993, days_ago: 5, id: "PIX-ATRASADO")
    assert_predicate @promise.reload, :state_fulfilled?
  end

  test "R198: com a política 'continua quebrada' o pagamento é comum" do
    @promise.update!(policies: @promise.policies.merge("after_break" => "stays_broken"))
    travel_day(Date.new(2026, 11, 3))
    Promises::Daily.new(@alfa).apply
    pay("PRM-000001", 157_993, days_ago: 5, id: "PIX-ATRASADO")

    assert_predicate @promise.reload, :state_broken?
    assert_not Payment.find_by(identifier: "PIX-ATRASADO").promise_counted
  end

  test "R199: o estorno do pagamento reabre a cumprida no prazo e quebra a que já passou dele" do
    pay("PRM-000001", 157_993, id: "PIX-R")
    assert_predicate @promise.reload, :state_fulfilled?
    travel_day(Date.new(2026, 10, 30))
    run_payments_import([ reversal_line("identificador_pagamento" => "PIX-R", "valor" => "1.579,93", "data_estorno" => brl_date(0)) ], kind: "reversals", confirm: true)

    assert_predicate @promise.reload, :state_open?
    assert_equal 0, @promise.paid_cents
    assert_equal %w[active active], [ @nf1, @nf2 ].map { |bill| bill.reload.status }
    assert_equal 2, @promise.promise_bills.where(held: true).count
  end

  test "R199: estorno depois do prazo deixa a promessa quebrada" do
    pay("PRM-000001", 157_993, id: "PIX-R")
    travel_day(Date.new(2026, 11, 4))
    run_payments_import([ reversal_line("identificador_pagamento" => "PIX-R", "valor" => "1.579,93", "data_estorno" => brl_date(0)) ], kind: "reversals", confirm: true)

    assert_predicate @promise.reload, :state_broken?
  end

  test "DP1: com 'também os pagamentos diretos', o pagamento direto ao título pelo meio combinado conta" do
    @promise.update!(policies: @promise.policies.merge("counting" => "also_direct"))
    pay("NF-1", 106_000, id: "DIRETO")

    payment = Payment.find_by(identifier: "DIRETO")
    assert_equal @promise, payment.promise
    assert payment.promise_counted
    assert_operator @promise.reload.paid_cents, :>, 0
  end

  test "DP-T: cumprida quando o pago chega ao percentual da política; o resto continua devido" do
    @promise.update!(policies: @promise.policies.merge("min_paid_pct" => 95))
    pay("PRM-000001", 155_000)

    assert_predicate @promise.reload, :state_fulfilled?
    assert_predicate @nf2.reload, :active?
  end

  test "DP11: com a política 'a R46 vale na promessa', o pagamento menor que o valor vira crédito sem baixar" do
    @alfa.setting.update!(partial_payment_policy: "credit")
    @promise.update!(policies: @promise.policies.merge("partial" => "r46"))
    pay("PRM-000001", 50_000)

    payment = Payment.find_by(promise: @promise)
    assert_equal 50_000, payment.credit_cents
    assert_equal 0, payment.applied_cents
    assert_predicate @nf1.reload, :active?
  end

  test "R202: o título retirado numa carga completa sai da promessa; sem nenhum título ela é cancelada" do
    run_portfolio_import([ csv_line("documento" => @customer.document, "nome" => @customer.name, "contrato" => "CT-1", "titulo" => "NF-1",
                                    "vencimento" => ChargesTestHelper::DUE.strftime("%d/%m/%Y"), "valor" => "1.000,00") ], mode: :full_sync, confirm: true)

    assert_predicate @promise.reload, :state_open?
    assert_equal [ @nf1.id ], @promise.promise_bills.where(removed_at: nil).pluck(:bill_id)
    assert_equal @promise.promise_bills.find_by(bill: @nf1).total_cents, @promise.total_cents

    run_portfolio_import([ csv_line("documento" => "111.444.777-35", "nome" => "Outro", "contrato" => "CT-5", "titulo" => "X-1", "vencimento" => "01/09/2026", "valor" => "10,00") ],
                         mode: :full_sync, confirm: true)
    assert_predicate @promise.reload, :state_canceled?
    assert_equal "títulos fora da cobrança", @promise.reason
  end

  test "R202a: o título que a carga passa a outro contrato sai da promessa" do
    run_portfolio_import([ csv_line("documento" => @customer.document, "nome" => @customer.name, "contrato" => "CT-2", "titulo" => "NF-2",
                                    "vencimento" => "15/09/2026", "valor" => "500,00") ], confirm: true)

    assert_equal [ @nf1.id ], @promise.reload.promise_bills.where(removed_at: nil).pluck(:bill_id)
  end

  test "V10 e MT-10: o mesmo número em dois credores é resolvido só no credor da importação" do
    beta = tenants(:beta)
    make_channel(beta)
    travel_day(TODAY)
    customer_b, bill_b, = promise_scenario(beta, charges: false, document: PaymentsHelper::JOAO, contract_code: "CT-B", name: "João")
    promise_b = register_promise(customer_b, [ bill_b ], user: users(:ana))
    travel_day(Date.new(2026, 10, 29))
    assert_equal "PRM-000001", promise_b.number

    line = payment_line("identificador" => "PIX-B", "documento" => PaymentsHelper::JOAO, "titulo" => "PRM-000001", "valor" => Money.format(promise_b.total_cents))
    run_payments_import([ line ], tenant: beta, user: users(:ana), confirm: true)

    assert_predicate promise_b.reload, :state_fulfilled?
    assert_predicate @promise.reload, :state_open?
  end

  test "a carga de carteira recusa título com o formato de número de promessa" do
    import = run_portfolio_import([ csv_line("titulo" => "PRM-000123") ])

    assert_equal 1, import.rejections.count
    assert_includes import.rejections.first.reason, "PRM-"
  end

  test "o job diário percorre os credores" do
    travel_day(Date.new(2026, 11, 3))
    perform_enqueued_jobs { PromisesDispatchJob.perform_now }

    assert_predicate @promise.reload, :state_broken?
    assert_equal "succeeded", TaskRun.where(name: Promises::Daily::NAME, tenant: @alfa).last.status
  end
end
