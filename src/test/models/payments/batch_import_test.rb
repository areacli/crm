require "test_helper"
require "active_job/continuation/test_helper"

# Processamento em lote das importações de pagamentos e estornos (decisão 0021, parte 2): lotes retomáveis, auditoria única, falha parcial e reenvio,
# importação presa.
class Payments::BatchImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActiveJob::Continuation::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @channel = make_channel(@alfa)
    @joana = users(:joana)
    @bills = [ make_bill(@alfa, number: "NF-1", amount_cents: 100_000),
               make_bill(@alfa, number: "NF-2", amount_cents: 50_000, document: JOAO, contract_code: "CT-2"),
               make_bill(@alfa, number: "NF-3", amount_cents: 30_000, contract_code: "CT-3") ]
  end

  def lines
    [ payment_line("identificador" => "P1", "titulo" => "NF-1", "valor" => "1.000,00"),
      payment_line("identificador" => "P2", "titulo" => "NF-2", "documento" => JOAO, "valor" => "200,00"),
      payment_line("identificador" => "P3", "titulo" => "NF-3", "valor" => "400,00") ]
  end

  def with_lots(size)
    previous = [ Payments::Processor.lot_size, Payments::ReversalProcessor.lot_size ]
    Payments::Processor.lot_size = Payments::ReversalProcessor.lot_size = size
    yield
  ensure
    Payments::Processor.lot_size, Payments::ReversalProcessor.lot_size = previous
  end

  test "os jobs de pagamentos e estornos são retomáveis, como os da carteira" do
    assert_includes CheckImportJob.ancestors, ActiveJob::Continuable
    assert_includes ConfirmImportJob.ancestors, ActiveJob::Continuable
  end

  test "a confirmação interrompida depois do primeiro lote retoma do cursor e dá o mesmo resultado de uma confirmação sem interrupção" do
    import = run_payments_import(lines)
    expected = import.summary_data[:effect].to_h.transform_values(&:to_i)
    Portfolio::ImportService.new.confirm(import)

    with_lots(1) do
      interrupt_job_during_step(ConfirmImportJob, :apply, cursor: 1) { perform_enqueued_jobs(only: ConfirmImportJob) }
      assert import.reload.confirming?
      assert_equal 1, Payment.count, "só o primeiro lote foi gravado"
      perform_enqueued_jobs(only: ConfirmImportJob)
    end
    import.reload
    assert import.confirmed?
    assert_equal 3, Payment.count
    assert_equal [ 100_000, 20_000, 30_000 ], @bills.map { |bill| bill.reload.paid_cents }
    assert_equal expected, import.summary_data[:confirmed_effect].to_h.transform_values(&:to_i), "o resumo da confirmação é o da conferência, mesmo com a interrupção"
    assert_equal 0, PaymentRow.where(import_id: import.id).count
  end

  test "a auditoria da baixa é a das telas: cada mudança leva a importação e o usuário que enviou" do
    import = run_payments_import(lines, confirm: true)

    changes = Change.where(import_id: import.id)
    assert_equal 3, changes.where(event: "payment_applied").count
    assert_equal [ @joana.id ], changes.pluck(:user_id).uniq
    assert_equal [ "bill" ], changes.where(event: "payment_applied").pluck(:subject_type).uniq
    assert_equal 1, changes.where(event: "credit_added").count, "o excedente de R$ 100,00 do primeiro pagamento"
  end

  test "a falha no segundo lote desfaz o lote e deixa o primeiro; enviar o mesmo arquivo ignora o já registrado e conclui" do
    import = run_payments_import(lines)
    calls = 0
    original = PaymentAllocation.method(:insert_all!)
    with_lots(1) do
      PaymentAllocation.define_singleton_method(:insert_all!) { |*args, **kwargs| (calls += 1) >= 2 ? raise("falha de teste") : original.call(*args, **kwargs) }
      begin
        Portfolio::ImportService.new.confirm(import)
        2.times { perform_enqueued_jobs(only: ConfirmImportJob) }
      ensure
        PaymentAllocation.define_singleton_method(:insert_all!, original)
      end
    end
    assert import.reload.failed?, "#{import.status} #{import.failure_reason}"
    assert_equal [ 1, 100_000, 0 ], [ Payment.count, @bills.first.reload.paid_cents, @bills.second.reload.paid_cents ], "o lote em curso foi desfeito inteiro; o anterior ficou"
    assert_equal 0, PaymentRow.where(import_id: import.id).count

    again = run_payments_import(lines)
    assert_equal 1, again.summary_data[:ignored], "o pagamento já registrado é ignorado"
    assert confirm_import(again).confirmed?
    assert_equal 3, Payment.count
    assert_equal [ 100_000, 20_000, 30_000 ], @bills.map { |bill| bill.reload.paid_cents }
  end

  test "a conferência interrompida na leitura retoma da última linha gravada, sem duplicar linhas nem recusas" do
    rows = lines + [ payment_line("identificador" => "P4", "titulo" => "") ]
    import = Portfolio::ImportService.new.start(tenant: @alfa, user: @joana, file: write_csv(rows, header: PaymentsHelper::PAYMENT_HEADER), mode: :incremental, kind: "payments")
    previous = Payments::Staging.batch_size
    Payments::Staging.batch_size = 2
    begin
      interrupt_job_during_step(CheckImportJob, :read, cursor: 3) { perform_enqueued_jobs(only: CheckImportJob) }
      assert import.reload.checking?
      assert_equal 2, PaymentRow.where(import_id: import.id).count
      perform_enqueued_jobs(only: CheckImportJob)
    ensure
      Payments::Staging.batch_size = previous
    end
    import.reload
    assert import.checked?
    assert_equal [ 3, 1 ], [ import.summary_data[:valid], import.summary_data[:rejected] ]
    assert_equal 3, PaymentRow.where(import_id: import.id, pending_payment_id: nil).count
  end

  test "o estorno em lotes pequenos dá o mesmo resultado do estorno em um lote só" do
    run_payments_import(lines, confirm: true)
    reversals = [ reversal_line("identificador_pagamento" => "P1", "identificador_estorno" => "E1", "valor" => "300,00"),
                  reversal_line("identificador_pagamento" => "P2", "identificador_estorno" => "E2", "valor" => "200,00"),
                  reversal_line("identificador_pagamento" => "P3", "identificador_estorno" => "E3", "valor" => "100,00") ]
    import = run_payments_import(reversals, kind: "reversals")
    with_lots(1) do
      interrupt_job_during_step(ConfirmImportJob, :apply, cursor: 2) { Portfolio::ImportService.new.confirm(import); perform_enqueued_jobs(only: ConfirmImportJob) }
      assert_equal 2, PaymentReversal.count
      perform_enqueued_jobs(only: ConfirmImportJob)
    end
    assert import.reload.confirmed?, "#{import.status} #{import.failure_reason} #{import.batch_state}"
    assert_equal 3, PaymentReversal.count, import.summary.inspect + ImportRejection.where(import_id: import.id).pluck(:reason).inspect
    assert_equal [ 70_000, 0, 30_000 ], @bills.map { |bill| bill.reload.paid_cents }
    assert_equal 2, Change.where(import_id: import.id, event: "payment_reversed").count, "o terceiro estorno saiu só do crédito"
  end

  test "a importação presa há mais de 30 minutos vira falhou, libera o credor e avisa no sino de quem enviou" do
    import = Portfolio::ImportService.new.start(tenant: @alfa, user: @joana, file: write_csv(lines, header: PaymentsHelper::PAYMENT_HEADER), mode: :incremental, kind: "payments")
    import.update_columns(status: "confirming", updated_at: 31.minutes.ago)
    fresh = Import.create!(tenant: tenants(:beta), user: users(:ana), kind: "portfolio", mode: "incremental", status: "checking", size_bytes: 0)

    assert_equal 1, Portfolio::StaleImports.new.call
    assert_equal [ "failed", "tempo-limite" ], [ import.reload.status, import.failure_reason ]
    assert fresh.reload.checking?, "a que avançou há pouco continua"
    assert_equal [ "import_stalled" ], Notice.where(user: @joana).pluck(:kind)
    assert_nothing_raised { Portfolio::ImportService.new.start(tenant: @alfa, user: @joana, file: write_csv(lines, header: PaymentsHelper::PAYMENT_HEADER), mode: :incremental, kind: "payments") }
  end

  test "a conferência esperando o gestor não é importação presa" do
    import = run_payments_import(lines)
    import.update_columns(updated_at: 2.hours.ago)
    assert_equal 0, Portfolio::StaleImports.new.call
    assert import.reload.checked?
  end
end
