require "test_helper"

# Critérios de aceite e regras R45 a R59 da especificação 03: conferência (nada é gravado) e confirmação (numa transação).
class Payments::PaymentImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @channel = make_channel(@alfa)
    @bill = make_bill(@alfa, number: "NF-1", amount_cents: 100_000)
  end

  def effect(import) = import.summary_data[:effect]

  test "a conferência mostra um título quitado e não grava nada; a confirmação baixa o título (critério 1)" do
    import = run_payments_import([ payment_line ])

    assert_predicate import, :checked?
    assert_equal 1, effect(import)[:settled]
    assert_equal "1.000,00", import.summary_data[:amount_formatted]
    assert_equal 0, Payment.count
    assert_equal "active", @bill.reload.status

    confirm_import(import)
    @bill.reload
    assert_equal [ "paid", 100_000, Date.current - 1 ], [ @bill.status, @bill.paid_cents, @bill.paid_on ]
    payment = Payment.sole
    assert_equal [ "applied", 100_000, 0, @channel.id ], [ payment.status, payment.applied_cents, payment.credit_cents, payment.channel_id ]
    assert_equal 0, Portfolio::Sql.rows("select 1 from payment_rows where import_id = #{import.id}").size
    assert_not File.exist?(import.file_path)
    assert_equal 0, Bill.active.where(tenant: @alfa).count
  end

  test "enviar de novo o mesmo arquivo confirmado: um pagamento já registrado, ignorado, e nada muda (critério 2)" do
    confirm_import(run_payments_import([ payment_line ]))
    before = [ Payment.count, Credit.count, @bill.reload.paid_cents ]

    again = run_payments_import([ payment_line ])
    assert_equal [ 1, 0, 0 ], [ again.summary_data[:ignored], again.summary_data[:valid], again.summary_data[:rejected] ]
    assert_equal "pagamento já registrado, ignorado", again.rejections.sole.reason
    assert_predicate again.rejections.sole, :ignored?
    confirm_import(again)
    assert_equal before, [ Payment.count, Credit.count, @bill.reload.paid_cents ]
  end

  test "mesmo canal e identificador nas linhas 2 e 3: a segunda é recusada (critério 3)" do
    import = run_payments_import([ payment_line, payment_line("valor" => "5,00") ])
    assert_equal [ 1, 1 ], [ import.summary_data[:valid], import.summary_data[:rejected] ]
    assert_equal "pagamento repetido na linha 2", import.rejections.sole.reason
    assert_equal 3, import.rejections.sole.line
  end

  test "o mesmo identificador em dois canais do credor registra os dois (critério 4)" do
    make_channel(@alfa, code: "CARTAO-1")
    other = make_bill(@alfa, number: "NF-2", amount_cents: 50_000, document: JOAO, contract_code: "CT-2", name: "João")
    import = confirm_import(run_payments_import([ payment_line, payment_line("canal" => "CARTAO-1", "titulo" => "NF-2", "documento" => JOAO, "valor" => "500,00") ]))
    assert_equal 2, Payment.count
    assert_predicate other.reload, :paid?
    assert_predicate import, :confirmed?
  end

  test "baixa parcial por padrão: o saldo cai e o título continua na lista (critério 5)" do
    confirm_import(run_payments_import([ payment_line("valor" => "400,00") ]))
    @bill.reload
    assert_equal [ "active", 40_000, 60_000 ], [ @bill.status, @bill.paid_cents, @bill.balance_cents ]
    assert_nil @bill.paid_on
    assert_equal 0, Credit.count
  end

  test "política crédito sem baixar: o título fica como está e o contrato ganha o crédito (critério 6)" do
    @alfa.setting.update!(partial_payment_policy: :credit)
    confirm_import(run_payments_import([ payment_line("valor" => "400,00") ]))
    assert_equal 0, @bill.reload.paid_cents
    credit = Credit.sole
    assert_equal [ @bill.contract_id, 40_000, "without_settling", "entry" ], [ credit.contract_id, credit.amount_cents, credit.reason, credit.kind ]
    assert_equal 40_000, @bill.contract.credit_cents
  end

  test "o excedente vira crédito do contrato do título, com o motivo excedente (critério 7, R50a)" do
    @bill.update!(paid_cents: 40_000)
    confirm_import(run_payments_import([ payment_line("valor" => "650,00") ]))
    assert_predicate @bill.reload, :paid?
    credit = Credit.sole
    assert_equal [ 5_000, "excess", @bill.contract_id ], [ credit.amount_cents, credit.reason, credit.contract_id ]
    assert_equal Payment.sole.id, credit.payment_id
  end

  test "pagamento sem título é recusado e não gera crédito (critério 8, R52a)" do
    import = run_payments_import([ payment_line("titulo" => "") ])
    assert_equal "título não informado", import.rejections.sole.reason
    assert_equal 0, effect(import)[:credits].to_i
  end

  test "título fora da carteira fica pendente, sem crédito, e a conferência seguinte o aplica quando a carteira o traz (critério 9, R52)" do
    import = confirm_import(run_payments_import([ payment_line("titulo" => "NF-9000", "identificador" => "PIX-9", "valor" => "300,00") ]))
    assert_equal 1, import.summary_data[:confirmed_effect][:pending_new]
    pending = Payment.sole
    assert_equal [ "pending", nil, 0 ], [ pending.status, pending.bill_id, Credit.count ]

    late = make_bill(@alfa, number: "NF-9000", amount_cents: 30_000)
    second = run_payments_import([ payment_line("identificador" => "PIX-10", "valor" => "10,00") ])
    assert_equal 1, effect(second)[:pending_applied]
    confirm_import(second)
    assert_predicate late.reload, :paid?
    assert_equal [ "applied", late.id ], [ pending.reload.status, pending.bill_id ]
  end

  test "canal não cadastrado, canal desativado, meio fora da lista e data futura são recusados (critérios 10 e 11, R49)" do
    make_channel(@alfa, code: "DESATIVADO", active: false)
    lines = [ payment_line("canal" => "341-1234-5678", "identificador" => "A"), payment_line("meio" => "cheque", "identificador" => "B"),
              payment_line("data_pagamento" => (Date.current + 1).strftime("%d/%m/%Y"), "identificador" => "C"),
              payment_line("canal" => "DESATIVADO", "identificador" => "D"), payment_line("valor" => "0,00", "identificador" => "E"),
              payment_line("documento" => "111.111.111-11", "identificador" => "F"), payment_line("identificador" => "G") ]
    reasons = run_payments_import(lines).rejections.order(:line).pluck(:line, :reason).to_h
    assert_equal "canal não cadastrado ou desativado", reasons[2]
    assert_equal "meio de pagamento fora da lista", reasons[3]
    assert_equal "data de pagamento futura", reasons[4]
    assert_equal "canal não cadastrado ou desativado", reasons[5]
    assert_equal "valor deve ser maior que zero", reasons[6]
    assert_equal "CPF inválido", reasons[7]
    assert_nil reasons[8]
  end

  test "título pago que volta numa carga de carteira continua pago e a conferência diz 'pago neste sistema, mantido' (critério 12, R57)" do
    confirm_import(run_payments_import([ payment_line ]))
    carteira = Portfolio::ImportService.new.start(tenant: @alfa, user: users(:joana), mode: :incremental, original_name: "c.csv",
                                                    file: write_csv([ csv_line("documento" => MARIA, "contrato" => "CT-1", "titulo" => "NF-1", "valor" => "1.500,00") ]))
    perform_enqueued_jobs(only: CheckImportJob)
    assert_equal 1, carteira.reload.summary_data[:bills_paid_kept]
    confirm_import(carteira)
    @bill.reload
    assert_equal [ "paid", 100_000 ], [ @bill.status, @bill.amount_cents ]
  end

  test "outro pagamento para título já pago vira crédito do contrato, com o motivo título já pago (R51)" do
    confirm_import(run_payments_import([ payment_line ]))
    confirm_import(run_payments_import([ payment_line("identificador" => "PIX-2", "valor" => "200,00") ]))
    credit = Credit.sole
    assert_equal [ 20_000, "already_paid", @bill.contract_id ], [ credit.amount_cents, credit.reason, credit.contract_id ]
    assert_predicate @bill.reload, :paid?
  end

  test "título retirado: o pagamento prevalece e quita; com a política vira crédito, fica retirado e o contrato ganha crédito (R46a)" do
    @bill.update!(status: :withdrawn, withdrawn_at: Time.current)
    confirm_import(run_payments_import([ payment_line ]))
    assert_predicate @bill.reload, :paid?

    other = make_bill(@alfa, number: "NF-7", amount_cents: 50_000, document: JOAO, contract_code: "CT-7", status: :withdrawn)
    @alfa.setting.update!(withdrawn_payment_policy: :credit)
    confirm_import(run_payments_import([ payment_line("identificador" => "PIX-7", "documento" => JOAO, "titulo" => "NF-7", "valor" => "500,00") ]))
    assert_predicate other.reload, :withdrawn?
    credit = Credit.find_by!(contract_id: other.contract_id)
    assert_equal [ 50_000, "withdrawn" ], [ credit.amount_cents, credit.reason ]
  end

  test "dois pagamentos para o mesmo título são aplicados na ordem da data (R53)" do
    @bill.update!(amount_cents: 50_000)
    lines = [ payment_line("identificador" => "B", "data_pagamento" => brl_date(1), "valor" => "300,00"),
              payment_line("identificador" => "A", "data_pagamento" => brl_date(3), "valor" => "300,00") ]
    confirm_import(run_payments_import(lines))
    assert_predicate @bill.reload, :paid?
    assert_equal [ 30_000, 20_000 ], Payment.order(:paid_on).pluck(:applied_cents)
    assert_equal [ 0, 10_000 ], Payment.order(:paid_on).pluck(:credit_cents)
    assert_equal 10_000, @bill.contract.credit_cents
  end

  test "o pagador pode ser um terceiro: o pagamento baixa o título e o documento fica no registro (R50a)" do
    confirm_import(run_payments_import([ payment_line("documento" => JOAO, "valor" => "1.200,00") ]))
    assert_predicate @bill.reload, :paid?
    assert_equal [ "applied", JOAO.delete(".-") ], [ Payment.sole.status, Payment.sole.document ]
    assert_equal 20_000, @bill.contract.credit_cents
  end

  test "número de título que se repete entre clientes é ambíguo para um terceiro: o pagamento fica pendente (R50a)" do
    make_bill(@alfa, number: "NF-1", amount_cents: 80_000, document: "111.444.777-35", contract_code: "CT-3", name: "Ana")
    confirm_import(run_payments_import([ payment_line("documento" => JOAO, "valor" => "800,00") ]))
    assert_equal "pending", Payment.sole.status
    assert_equal [ 0, 0 ], Bill.where(number: "NF-1").pluck(:paid_cents)
  end

  test "o crédito é do contrato, visível a todos os clientes dele, sem saldo por cliente (R55b)" do
    pedro = Customer.create!(tenant: @alfa, document: Document.normalize(JOAO), name: "Pedro")
    ContractCustomer.create!(contract: @bill.contract, customer: pedro)
    confirm_import(run_payments_import([ payment_line("valor" => "1.200,00") ]))
    assert_equal 20_000, @bill.contract.credit_cents
    assert_equal [ @bill.contract_id ], Credit.pluck(:contract_id)
    assert_not Customer.column_names.include?("credit_cents")
  end

  test "a unicidade é por credor: o mesmo canal e identificador em outro credor são outro pagamento (R48a)" do
    beta = tenants(:beta)
    make_channel(beta)
    make_bill(beta, number: "NF-1", amount_cents: 100_000)
    confirm_import(run_payments_import([ payment_line ]))
    import = confirm_import(run_payments_import([ payment_line ], tenant: beta, user: users(:ana)))
    assert_equal [ 1, 1 ], [ Payment.where(tenant: @alfa).count, Payment.where(tenant: beta).count ]
    assert_predicate import, :confirmed?
  end

  test "a linha com o canal de outro credor é recusada e o título de outro credor fica pendente (V10)" do
    beta = tenants(:beta)
    make_channel(beta, code: "SO-BETA")
    make_bill(beta, number: "NF-B", amount_cents: 10_000, document: JOAO)
    import = run_payments_import([ payment_line("canal" => "SO-BETA"), payment_line("identificador" => "X", "titulo" => "NF-B", "documento" => JOAO) ])
    assert_equal "canal não cadastrado ou desativado", import.rejections.sole.reason
    confirm_import(import)
    assert_equal "pending", Payment.sole.status
    assert_predicate Bill.find_by!(number: "NF-B"), :active?
  end

  test "uma importação de carteira em andamento impede a de pagamentos no mesmo credor (R10)" do
    Portfolio::ImportService.new.start(tenant: @alfa, user: users(:joana), file: write_csv([ csv_line ]), mode: :incremental)
    assert_raises(Portfolio::ImportRefused) do
      Portfolio::ImportService.new.start(tenant: @alfa, user: users(:joana), file: write_csv([ payment_line ], header: PaymentsHelper::PAYMENT_HEADER), mode: :incremental, kind: "payments")
    end
  end

  test "a planilha-modelo passa na conferência quando o canal e os títulos existem (R44)" do
    make_bill(@alfa, number: "NF-1024/3", amount_cents: 100_000)
    make_bill(@alfa, number: "NF-1025/1", amount_cents: 100_000, document: "390.533.447-05", contract_code: "CT-2")
    path = Tempfile.new([ "modelo", ".csv" ]).tap { |file| file.binmode; file.write(Payments::SheetModel.csv("payments")); file.close }.path
    import = Portfolio::ImportService.new.start(tenant: @alfa, user: users(:joana), file: path, mode: :incremental, kind: "payments")
    perform_enqueued_jobs(only: CheckImportJob)
    summary = import.reload.summary_data
    assert_equal [ 2, 0 ], [ summary[:valid], summary[:rejected] ]
  end

  test "a confirmação transmite o andamento ao canal do credor (sem polling)" do
    run_payments_import([ payment_line ])
    assert_operator ActionCable.server.pubsub.broadcasts(ImportsChannel.broadcasting_for(@alfa)).size, :>=, 3
  end

  test "o resumo da conferência tem as contas da especificação (R56)" do
    @alfa.setting.update!(partial_payment_policy: :credit)
    make_bill(@alfa, number: "NF-2", amount_cents: 100_000, document: JOAO, contract_code: "CT-2")
    lines = [ payment_line, payment_line("identificador" => "P2", "documento" => JOAO, "titulo" => "NF-2", "valor" => "250,00"),
              payment_line("identificador" => "P3", "titulo" => "NF-77"), payment_line("identificador" => "P4", "titulo" => "") ]
    summary = run_payments_import(lines).summary_data
    assert_equal [ 4, 3, 1 ], [ summary[:lines], summary[:valid], summary[:rejected] ]
    assert_equal [ 1, 0, 1, 25_000, 1 ], summary[:effect].values_at(:settled, :partial, :credits, :credit_cents, :pending_new).map(&:to_i)
  end
end
