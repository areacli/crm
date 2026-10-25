require "test_helper"

# Estornos (R60 a R64): arquivo próprio, parcial aceito, o valor sai primeiro do crédito e depois do título, que volta à cobrança.
class Payments::ReversalImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @channel = make_channel(@alfa)
    @bill = make_bill(@alfa, number: "NF-1", amount_cents: 100_000)
  end

  def pay(value, id: "PIX-1", number: "NF-1", document: MARIA)
    confirm_import(run_payments_import([ payment_line("valor" => value, "identificador" => id, "titulo" => number, "documento" => document) ]))
  end

  def reverse(value, payment_id: "PIX-1", id: "EST-1", confirm: true, **options)
    run_payments_import([ reversal_line("valor" => value, "identificador_pagamento" => payment_id, "identificador_estorno" => id) ], kind: "reversals", confirm: confirm, **options)
  end

  test "estorno parcial: sai primeiro do crédito e depois do título, que volta à cobrança com o saldo reaberto (critério, R62)" do
    pay("1.050,00")
    assert_predicate @bill.reload, :paid?
    assert_equal 5_000, @bill.contract.credit_cents

    checked = reverse("300,00", confirm: false)
    assert_equal [ 1, 1, 1 ], checked.summary_data[:effect].values_at(:reopened, :credit_reduced, :from_bill_cents).then { |a, b, c| [ a, b, c / 25_000 ] }
    assert_predicate @bill.reload, :paid?, "a conferência não grava nada"

    confirm_import(checked)
    @bill.reload
    assert_equal [ "active", 75_000, 25_000, nil ], [ @bill.status, @bill.paid_cents, @bill.balance_cents, @bill.paid_on ]
    assert_equal 0, @bill.contract.credit_cents
    reversal = PaymentReversal.sole
    assert_equal [ 5_000, 25_000, 30_000 ], [ reversal.from_credit_cents, reversal.from_bill_cents, reversal.amount_cents ]
    assert_equal 30_000, Payment.sole.reversed_cents
  end

  test "valor maior que o saldo estornável é recusado, com o saldo na mensagem (critério)" do
    pay("400,00")
    reverse("100,00")
    import = reverse("350,00", id: "EST-2", confirm: false)
    assert_equal "valor maior que o saldo estornável de R$ 300,00", import.rejections.sole.reason
  end

  test "somar linhas do mesmo arquivo respeita o saldo estornável" do
    pay("400,00")
    import = run_payments_import([ reversal_line("valor" => "250,00", "identificador_estorno" => "A"), reversal_line("valor" => "200,00", "identificador_estorno" => "B") ],
                                 kind: "reversals")
    assert_equal [ 1, 1 ], [ import.summary_data[:valid], import.summary_data[:rejected] ]
    assert_equal "valor maior que o saldo estornável de R$ 150,00", import.rejections.sole.reason
  end

  test "o mesmo arquivo de estornos já confirmado é ignorado (critério)" do
    pay("400,00")
    reverse("100,00")
    again = reverse("100,00", confirm: false)
    assert_equal [ 1, 0, 0 ], [ again.summary_data[:ignored], again.summary_data[:valid], again.summary_data[:rejected] ]
    assert_equal "estorno já registrado, ignorado", again.rejections.sole.reason
    confirm_import(again)
    assert_equal [ 1, 10_000 ], [ PaymentReversal.count, Payment.sole.reversed_cents ]
  end

  test "estorno repetido no arquivo, pagamento inexistente e data anterior ao pagamento são recusados (R61)" do
    pay("400,00")
    lines = [ reversal_line("identificador_estorno" => "A", "valor" => "10,00"), reversal_line("identificador_estorno" => "A", "valor" => "10,00"),
              reversal_line("identificador_estorno" => "B", "identificador_pagamento" => "NAO-EXISTE"),
              reversal_line("identificador_estorno" => "C", "data_estorno" => brl_date(5)),
              reversal_line("identificador_estorno" => "D", "data_estorno" => (Date.current + 2).strftime("%d/%m/%Y")) ]
    reasons = run_payments_import(lines, kind: "reversals").rejections.order(:line).pluck(:line, :reason).to_h
    assert_equal "estorno repetido na linha 2", reasons[3]
    assert_equal "pagamento não encontrado no canal", reasons[4]
    assert_equal "data do estorno anterior ao pagamento", reasons[5]
    assert_equal "data de estorno futura", reasons[6]
  end

  test "pagamento pendente estornado deixa de ser pendente pelo valor estornado (R62)" do
    confirm_import(run_payments_import([ payment_line("titulo" => "NF-X", "identificador" => "PIX-9", "valor" => "300,00") ]))
    reverse("300,00", payment_id: "PIX-9")
    payment = Payment.sole
    assert_equal [ "cancelled", 30_000 ], [ payment.status, payment.reversed_cents ]
    assert_equal 0, run_payments_import([ payment_line("identificador" => "PIX-20", "valor" => "1,00") ]).summary_data[:effect][:pending_applied].to_i
  end

  test "título retirado, quitado pelo pagamento e estornado: volta à cobrança (padrão) ou volta a retirado (R62a)" do
    @bill.update!(status: :withdrawn, withdrawn_at: Time.current)
    pay("1.000,00")
    assert_predicate @bill.reload, :paid?
    reverse("1.000,00")
    assert_equal [ "active", 100_000 ], [ @bill.reload.status, @bill.balance_cents ]

    other = make_bill(@alfa, number: "NF-7", amount_cents: 50_000, document: JOAO, contract_code: "CT-7", status: :withdrawn)
    other.update!(withdrawn_at: Time.current)
    @alfa.setting.update!(withdrawn_reversal_policy: :withdrawn)
    pay("500,00", id: "PIX-7", number: "NF-7", document: JOAO)
    reverse("500,00", payment_id: "PIX-7", id: "EST-7")
    assert_equal [ "withdrawn", 50_000 ], [ other.reload.status, other.balance_cents ]
  end

  test "título retirado com baixa parcial não muda de situação com o estorno (R62a)" do
    @bill.update!(status: :withdrawn, withdrawn_at: Time.current)
    pay("400,00")
    reverse("100,00")
    assert_equal [ "withdrawn", 30_000 ], [ @bill.reload.status, @bill.paid_cents ]
  end

  test "estorno de pagamento feito por canal desativado é aceito (revisão 5)" do
    pay("400,00")
    @channel.update!(active: false)
    import = reverse("100,00", confirm: false)
    assert_equal [ 1, 0 ], [ import.summary_data[:valid], import.summary_data[:rejected] ]
  end

  test "estorno de pagamento de outro credor é recusado como pagamento não encontrado (V10)" do
    beta = tenants(:beta)
    make_channel(beta)
    pay("400,00")
    import = reverse("100,00", tenant: beta, user: users(:ana), confirm: false)
    assert_equal "pagamento não encontrado no canal", import.rejections.sole.reason
    assert_equal 0, Payment.sole.reversed_cents
  end

  test "o histórico do título guarda o pagamento e o estorno (R59)" do
    pay("400,00")
    reverse("100,00")
    events = Change.where(subject_type: "bill", subject_id: @bill.id).order(:id).pluck(:event, :after)
    assert_equal [ [ "payment_applied", "40000" ], [ "payment_reversed", "30000" ] ], events
  end

  test "mês do estorno ou mês do pagamento no recuperado do resumo (R64)" do
    october = Date.new(2026, 10, 15)
    november = Date.new(2026, 11, 5)
    payment = Payment.create!(tenant: @alfa, channel: @channel, bill: @bill, identifier: "OUT", document: "52998224725", bill_number: "NF-1", paid_on: october,
                              amount_cents: 100_000, payment_method: :pix, status: :applied, applied_cents: 100_000)
    PaymentReversal.create!(tenant: @alfa, channel: @channel, payment: payment, identifier: "E", reversed_on: november, amount_cents: 40_000, from_bill_cents: 40_000)
    summary = -> { Portfolio::Summary.new(users(:joana), reference: november).for_tenant(@alfa)[:recovered].map { |month| month[:total_cents] } }

    assert_equal [ -40_000, 100_000 ], summary.call, "mês do estorno: outubro intacto, novembro com o estorno"
    @alfa.setting.update!(reversal_month_policy: :payment)
    assert_equal [ 0, 60_000 ], summary.call, "mês do pagamento: outubro já descontado"
  end
end
