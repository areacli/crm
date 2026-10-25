require "test_helper"

# Carteira revista (05): versões do valor (R88), saldo e excedente (R89, R90), estorno com excedente (R92), divergência e política
# (R93 a R98), tratamento (R99), histórico (R100), produto e acréscimos (R101 a R103).
class Portfolio::ValueDiscrepancyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { @alfa = tenants(:alfa) }

  def versions(bill) = bill.reload.value_versions.in_order.pluck(:amount_cents)

  test "R88: a versão 1 nasce com o título; valor novo cria versão e valor igual não cria" do
    bill = make_bill(@alfa, number: "NF-1", amount_cents: 10_000)
    assert_equal [ 10_000 ], versions(bill)

    run_portfolio_import([ bill_line("NF-1", "120,00") ], confirm: true)
    assert_equal [ 10_000, 12_000 ], versions(bill)
    version = bill.value_versions.in_order.last
    assert_equal [ users(:joana).id, Import.last.id ], [ version.user_id, version.import_id ]

    run_portfolio_import([ bill_line("NF-1", "120,00") ], confirm: true)
    assert_equal [ 10_000, 12_000 ], versions(bill)
    assert_equal 12_000, bill.reload.amount_cents
  end

  test "R88: título novo da carga ganha a versão 1" do
    run_portfolio_import([ bill_line("NF-9", "55,00") ], confirm: true)
    bill = Bill.find_by!(number: "NF-9")
    assert_equal [ 5_500 ], versions(bill)
  end

  test "R89: o saldo nunca é negativo e o excedente é calculado" do
    bill = Bill.new(amount_cents: 30_000, paid_cents: 40_000)
    assert_equal [ 0, 10_000 ], [ bill.balance_cents, bill.excess_cents ]
    bill = Bill.new(amount_cents: 100_000, paid_cents: 40_000)
    assert_equal [ 60_000, 0 ], [ bill.balance_cents, bill.excess_cents ]
  end

  test "R93, R94, R98 e critério: política seguir, título passa a pago, excedente de R$ 100,00 e divergência aberta" do
    bill = paid_bill
    checked = run_portfolio_import([ bill_line("NF-1024/3", "300,00") ])
    item = checked.summary_data[:discrepancies][:items].sole
    assert_equal 1, checked.summary_data[:discrepancies][:count]
    assert_equal [ "NF-1024/3", 100_000, 30_000, 40_000, 60_000, 0, 10_000, "becomes_paid" ],
                 item.values_at(:number, :previous_cents, :reported_cents, :allocated_cents, :balance_before_cents, :balance_after_cents, :excess_cents, :effect)
    assert_predicate bill.reload, :active?, "a conferência não grava nada"
    assert_equal 0, ValueDiscrepancy.count

    Portfolio::ImportService.new.confirm(checked, by: users(:joana))
    perform_enqueued_jobs(only: ConfirmImportJob)
    bill.reload
    assert_equal [ "paid", 30_000, 0, 10_000 ], [ bill.status, bill.amount_cents, bill.balance_cents, bill.excess_cents ]
    assert_not_nil bill.paid_on
    discrepancy = ValueDiscrepancy.sole
    assert_predicate discrepancy, :open?
    assert_predicate discrepancy, :effect_becomes_paid?
    assert_equal [ 100_000, 30_000, 40_000, 10_000 ], discrepancy.values_at(:previous_cents, :reported_cents, :allocated_cents, :excess_cents)
    assert_equal [ 100_000, 30_000 ], versions(bill)
    assert_equal 10_000, Portfolio::Summary.new(users(:joana)).for_tenant(@alfa)[:credit_cents]
  end

  test "R94 e critério: política manter e registrar deixa o título ativo com saldo de R$ 600,00" do
    set_discrepancy_policy("keep")
    bill = paid_bill
    run_portfolio_import([ bill_line("NF-1024/3", "300,00") ], confirm: true)
    bill.reload
    assert_equal [ "active", 100_000, 60_000 ], [ bill.status, bill.amount_cents, bill.balance_cents ]
    discrepancy = ValueDiscrepancy.sole
    assert_equal [ "kept", 30_000, "keep" ], [ discrepancy.effect, discrepancy.reported_cents, discrepancy.policy ]
    assert_equal [ 100_000 ], versions(bill)
  end

  test "R95: valor maior em título com baixa parcial, seguir sobe o saldo; manter não muda" do
    bill = paid_bill
    run_portfolio_import([ bill_line("NF-1024/3", "1.100,00") ], confirm: true)
    assert_equal [ 70_000, "balance_up" ], [ bill.reload.balance_cents, ValueDiscrepancy.sole.effect ]

    set_discrepancy_policy("keep")
    other = paid_bill(number: "NF-2", document: JOAO, contract_code: "CT-2", name: "João Pereira")
    run_portfolio_import([ bill_line("NF-2", "1.100,00", "documento" => JOAO, "nome" => "João Pereira", "contrato" => "CT-2") ], confirm: true)
    assert_equal 60_000, other.reload.balance_cents
    assert_equal "kept", ValueDiscrepancy.order(:id).last.effect
  end

  test "R95: valor menor que ainda deixa saldo, seguir faz o saldo cair" do
    bill = paid_bill
    run_portfolio_import([ bill_line("NF-1024/3", "700,00") ], confirm: true)
    assert_equal [ "active", 30_000, "balance_down" ], [ bill.reload.status, bill.balance_cents, ValueDiscrepancy.sole.effect ]
  end

  test "R96 e critério: título pago nunca muda; valor diferente gera divergência só para registro, valor igual não" do
    [ "seguir", "manter" ].each do |name|
      set_discrepancy_policy(name == "seguir" ? "follow" : "keep")
      bill = paid_bill(number: "NF-#{name}", amount_cents: 50_000, paid_cents: 50_000)
      assert_predicate bill, :paid?
      before = ValueDiscrepancy.count
      run_portfolio_import([ bill_line(bill.number, "520,00") ], confirm: true)
      bill.reload
      assert_equal [ "paid", 50_000, 0 ], [ bill.status, bill.amount_cents, bill.balance_cents ], name
      assert_equal "record_only", ValueDiscrepancy.order(:id).last.effect, name
      run_portfolio_import([ bill_line(bill.number, "500,00") ], confirm: true)
      assert_equal before + 1, ValueDiscrepancy.count, "valor igual não gera divergência (#{name})"
    end
  end

  test "R96: a conferência de título pago com valor igual continua 'pago neste sistema, mantido'" do
    bill = paid_bill(amount_cents: 50_000, paid_cents: 50_000)
    checked = run_portfolio_import([ bill_line(bill.number, "500,00") ])
    assert_equal 1, checked.summary_data[:bills_paid_kept]
    assert_equal 0, checked.summary_data[:discrepancies][:count]
  end

  test "R97 e critério: retirado com pagamento que volta com R$ 300,00 volta como pago, sem a marca de quitado retirado" do
    bill = paid_bill(number: "NF-0877/1", amount_cents: 50_000, paid_cents: 30_000)
    bill.update!(status: :withdrawn, withdrawn_at: Time.current)
    run_portfolio_import([ bill_line("NF-0877/1", "300,00") ], confirm: true)
    bill.reload
    assert_equal [ "paid", 0, nil ], [ bill.status, bill.balance_cents, bill.withdrawn_at ]
    assert_equal "returns_paid", ValueDiscrepancy.sole.effect
  end

  test "R97: retirado que volta com a política manter volta a ativo com o valor que tinha e o saldo restante" do
    set_discrepancy_policy("keep")
    bill = paid_bill(number: "NF-0877/1", amount_cents: 50_000, paid_cents: 30_000)
    bill.update!(status: :withdrawn, withdrawn_at: Time.current)
    run_portfolio_import([ bill_line("NF-0877/1", "300,00") ], confirm: true)
    bill.reload
    assert_equal [ "active", 50_000, 20_000 ], [ bill.status, bill.amount_cents, bill.balance_cents ]
  end

  test "R93: título sem alocação segue a R13, sem divergência" do
    bill = make_bill(@alfa, number: "NF-5", amount_cents: 10_000)
    run_portfolio_import([ bill_line("NF-5", "90,00") ], confirm: true)
    assert_equal [ 9_000, 0 ], [ bill.reload.amount_cents, ValueDiscrepancy.count ]
  end

  test "caso de exceção: política trocada entre a conferência e a confirmação refaz a conferência e recusa" do
    paid_bill
    checked = run_portfolio_import([ bill_line("NF-1024/3", "300,00") ])
    set_discrepancy_policy("keep")
    error = assert_raises(Portfolio::ImportRefused) { Portfolio::ImportService.new.confirm(checked, by: users(:joana)) }
    assert_match(/política de divergência mudou/, error.message)
    perform_enqueued_jobs(only: CheckImportJob)
    checked.reload
    assert_predicate checked, :checked?
    assert_equal "kept", checked.summary_data[:discrepancies][:items].sole[:effect]
  end

  test "caso de exceção: duas cargas seguidas criam duas versões e duas divergências; aplicar a antiga é recusado, manter não" do
    set_discrepancy_policy("keep")
    bill = paid_bill
    run_portfolio_import([ bill_line("NF-1024/3", "300,00") ], confirm: true)
    run_portfolio_import([ bill_line("NF-1024/3", "200,00") ], confirm: true)
    first, second = ValueDiscrepancy.order(:id).to_a
    Discrepancies::Handler.new(users(:joana)).call(second, note: "credor confirmou", choice: "apply")
    assert_equal 20_000, bill.reload.amount_cents
    error = assert_raises(Discrepancies::Refused) { Discrepancies::Handler.new(users(:joana)).call(first, note: "x", choice: "apply") }
    assert_match(/mudou depois desta divergência/, error.message)
    Discrepancies::Handler.new(users(:joana)).call(first, note: "mantido", choice: "keep")
    assert_predicate first.reload, :handled?
  end

  test "R99: tratar exige nota; manter não muda valor nem saldo; guarda quem, quando e a nota" do
    paid_bill
    run_portfolio_import([ bill_line("NF-1024/3", "300,00") ], confirm: true)
    discrepancy = ValueDiscrepancy.sole
    handler = Discrepancies::Handler.new(users(:joana))
    error = assert_raises(Discrepancies::Refused) { handler.call(discrepancy, note: "  ", choice: "keep") }
    assert_equal "Informe a nota.", error.message
    assert_predicate discrepancy.reload, :open?

    handler.call(discrepancy, note: "credor aplicou reajuste", choice: "keep")
    discrepancy.reload
    assert_equal [ "handled", "keep", "credor aplicou reajuste", users(:joana).id ], [ discrepancy.status, discrepancy.choice, discrepancy.note, discrepancy.handled_by_id ]
    assert_not_nil discrepancy.handled_at
    assert_raises(Discrepancies::Refused) { handler.call(discrepancy, note: "de novo", choice: "keep") }
  end

  test "R99 e critério: aplicar o valor informado na política manter cria a versão, quita e deixa excedente de R$ 100,00" do
    set_discrepancy_policy("keep")
    bill = paid_bill
    run_portfolio_import([ bill_line("NF-1024/3", "300,00") ], confirm: true)
    Discrepancies::Handler.new(users(:joana)).call(ValueDiscrepancy.sole, note: "credor confirmou o desconto", choice: "apply")
    bill.reload
    assert_equal [ "paid", 30_000, 10_000 ], [ bill.status, bill.amount_cents, bill.excess_cents ]
    assert_equal [ 100_000, 30_000 ], versions(bill)
    assert_equal "apply", ValueDiscrepancy.sole.choice
  end

  test "R99: aplicar não vale em divergência de título pago nem da política seguir" do
    paid = paid_bill(number: "NF-P", amount_cents: 50_000, paid_cents: 50_000)
    run_portfolio_import([ bill_line("NF-P", "520,00") ], confirm: true)
    discrepancy = ValueDiscrepancy.sole
    assert_not discrepancy.applicable?
    assert_raises(Discrepancies::Refused) { Discrepancies::Handler.new(users(:joana)).call(discrepancy, note: "x", choice: "apply") }
    assert_predicate discrepancy.reload, :open?
    assert_equal 50_000, paid.reload.amount_cents
  end

  test "R90 e R92: excedente some sozinho se o valor sobe e o estorno consome primeiro o excedente" do
    bill = paid_bill
    run_portfolio_import([ bill_line("NF-1024/3", "300,00") ], confirm: true)
    assert_equal 10_000, bill.reload.excess_cents
    run_portfolio_import([ bill_line("NF-1024/3", "350,00") ], confirm: true) # pago, não muda
    assert_equal [ "paid", 30_000, 10_000 ], [ bill.reload.status, bill.amount_cents, bill.excess_cents ]

    id = Payment.sole.identifier
    # Estorno de R$ 150,00: alocado 250, excedente zero, saldo 50 e volta à cobrança (critério).
    run_payments_import([ reversal_line("identificador_pagamento" => id, "valor" => "150,00") ], kind: "reversals", confirm: true)
    bill.reload
    assert_equal [ "active", 25_000, 0, 5_000, nil ], [ bill.status, bill.paid_cents, bill.excess_cents, bill.balance_cents, bill.paid_on ]
  end

  test "R92: estorno que só reduz o excedente não reabre o título" do
    bill = paid_bill
    run_portfolio_import([ bill_line("NF-1024/3", "300,00") ], confirm: true)
    run_payments_import([ reversal_line("identificador_pagamento" => Payment.sole.identifier, "valor" => "60,00") ], kind: "reversals", confirm: true)
    bill.reload
    assert_equal [ "paid", 34_000, 4_000 ], [ bill.status, bill.paid_cents, bill.excess_cents ]
    assert_not_nil bill.paid_on
  end

  test "R58: o excedente de valor reduzido não conta como recuperado" do
    paid_bill
    before = Portfolio::Summary.new(users(:joana)).for_tenant(@alfa)[:recovered].first[:total_cents]
    assert_equal 40_000, before
    run_portfolio_import([ bill_line("NF-1024/3", "300,00") ], confirm: true)
    summary = Portfolio::Summary.new(users(:joana)).for_tenant(@alfa)
    assert_equal 30_000, summary[:recovered].first[:total_cents]
    assert_equal 10_000, summary[:credit_cents]
  end

  test "R90: excedente de contrato com dois clientes é crédito do contrato, somado uma vez" do
    bill = paid_bill
    pedro = Customer.create!(tenant: @alfa, document: Document.normalize(JOAO), name: "Pedro")
    ContractCustomer.create!(contract: bill.contract, customer: pedro)
    run_portfolio_import([ bill_line("NF-1024/3", "300,00") ], confirm: true)
    assert_equal 10_000, Portfolio::Summary.new(users(:joana)).for_tenant(@alfa)[:credit_cents]
    assert_equal [ bill.id ], Bill.where(contract_id: pedro.contracts.ids).where("paid_cents > amount_cents").ids
  end

  test "R101: produto é guardado, aparece no histórico e vazio não apaga o anterior" do
    header = CsvHelper::HEADER + %w[produto]
    run_portfolio_import([ bill_line("NF-7", "10,00", "produto" => "CARTAO-GOLD") ], confirm: true, header: header)
    bill = Bill.find_by!(number: "NF-7")
    assert_equal "CARTAO-GOLD", bill.product
    run_portfolio_import([ bill_line("NF-7", "10,00", "produto" => "") ], confirm: true, header: header)
    assert_equal "CARTAO-GOLD", bill.reload.product
  end

  test "R102 e critério: multa informada pelo credor é guardada e mostrada na conferência, sem mudar valor nem saldo" do
    header = CsvHelper::HEADER + %w[multa_credor juros_credor]
    checked = run_portfolio_import([ bill_line("NF-8", "1.000,00", "multa_credor" => "20,00", "juros_credor" => "0,00") ], header: header)
    assert_equal [ 1, 2_000, 0 ], checked.summary_data[:reported_surcharges].values_at(:lines, :penalty_cents, :interest_cents)
    Portfolio::ImportService.new.confirm(checked, by: users(:joana))
    perform_enqueued_jobs(only: ConfirmImportJob)
    bill = Bill.find_by!(number: "NF-8")
    surcharge = ReportedSurcharge.find_by!(bill: bill)
    assert_equal [ 2_000, 0 ], [ surcharge.penalty_cents, surcharge.interest_cents ]
    assert_equal [ 100_000, 100_000 ], [ bill.amount_cents, bill.balance_cents ]
  end

  test "R103: acréscimo inválido ou negativo recusa a linha" do
    header = CsvHelper::HEADER + %w[juros_credor]
    checked = run_portfolio_import([ bill_line("NF-9", "10,00", "juros_credor" => "-5,00") ], header: header)
    assert_equal "juros_credor inválido", checked.rejections.sole.reason
    Portfolio::ImportService.new.discard(checked)
    checked = run_portfolio_import([ bill_line("NF-9", "10,00", "juros_credor" => "abc") ], header: header)
    assert_equal "juros_credor inválido", checked.rejections.sole.reason
  end

  test "R100: o histórico do título traz versões, pagamentos, estornos e divergências em ordem" do
    bill = paid_bill
    run_portfolio_import([ bill_line("NF-1024/3", "300,00") ], confirm: true)
    run_payments_import([ reversal_line("identificador_pagamento" => Payment.sole.identifier, "valor" => "150,00") ], kind: "reversals", confirm: true)
    history = Portfolio::BillHistory.new(bill.reload)
    assert_equal %i[version payment version discrepancy reversal].sort, history.events.map(&:kind).sort
    assert_equal [ 100_000, 30_000 ], history.versions.map(&:amount_cents)
  end

  test "V9 e propriedade: pago do título é a soma do aplicado menos o estornado do título depois de operações variadas" do
    bills = (1..4).map { |n| paid_bill(number: "NF-R#{n}", amount_cents: 10_000 * n, paid_cents: 0, document: MARIA, contract_code: "CT-1") }
    bills.each_with_index { |bill, index| pay_bill(bill, 3_000 * (index + 1), id: "P-#{index}") }
    run_portfolio_import(bills.each_with_index.map { |bill, index| bill_line(bill.number, Money.format(index.even? ? 5_000 : 45_000)) }, confirm: true)
    run_payments_import([ reversal_line("identificador_pagamento" => "P-2", "identificador_estorno" => "E-2", "valor" => "20,00"),
                          reversal_line("identificador_pagamento" => "P-0", "identificador_estorno" => "E-0", "valor" => "10,00") ], kind: "reversals", confirm: true)
    bills.each do |bill|
      bill.reload
      applied = Payment.where(bill_id: bill.id).sum(:applied_cents)
      reversed = PaymentReversal.joins(:payment).where(payments: { bill_id: bill.id }).sum(:from_bill_cents)
      assert_equal applied - reversed, bill.paid_cents, bill.number
      assert_operator bill.balance_cents, :>=, 0
      assert_equal bill.amount_cents, bill.value_versions.in_order.last.amount_cents, "a cópia do valor vigente"
    end
  end
end
