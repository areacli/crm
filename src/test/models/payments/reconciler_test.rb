require "test_helper"

# Conciliação diária dos pagamentos (12, parte D, R283): instrumentos ativos sem conferência há N dias, avisos que falharam, TaskRun do credor. Sem polling
# de tela e sem fornecedor real.
class PaymentsReconcilerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alfa = tenants(:alfa)
    @bill, @instrument = paid_scenario(kind: "pix")
    @reconciler = Payments::Reconciler.new(@alfa)
  end

  test "instrumento ativo nunca conferido, emitido há mais de N dias, entra; o recente e o pago não" do
    assert_empty @reconciler.due.to_a, "recém-emitido"
    @instrument.update_columns(issued_at: 4.days.ago)
    assert_equal [ @instrument ], @reconciler.due.to_a
    @instrument.update_columns(reconciled_at: 1.day.ago)
    assert_empty @reconciler.due.to_a, "conferido ontem"
    @instrument.update_columns(reconciled_at: 4.days.ago)
    assert_equal [ @instrument ], @reconciler.due.to_a
    @instrument.update_columns(state: "paid")
    assert_empty @reconciler.due.to_a
  end

  test "a execução enfileira um job por instrumento, espaçados pelo limite por minuto, e vira TaskRun do credor" do
    @instrument.update_columns(issued_at: 4.days.ago)
    other = emit(@alfa, @bill.customer, "pix", 100_000, reference: [ "bill", @bill.id ])
    other.update_columns(issued_at: 5.days.ago)
    run = nil
    assert_enqueued_jobs(2, only: ReconcileInstrumentJob) { run = @reconciler.call(per_minute: 30) }
    assert_equal [ "payment_reconciliation", "succeeded", 2, @alfa.id ], run.values_at(:name, :status, :processed, :tenant_id)
    assert_equal "Avisos reprocessados: 0; instrumentos a conferir: 2.", run.note
    waits = enqueued_jobs.select { |job| job["job_class"] == "ReconcileInstrumentJob" }.map { |job| job["scheduled_at"] }
    assert_in_delta 2.0, Time.iso8601(waits.max) - Time.iso8601(waits.min), 0.5
  end

  test "o job confere no fornecedor: pagou sem aviso, o instrumento é baixado; e a data da conferência avança" do
    @instrument.update_columns(issued_at: 4.days.ago)
    fake_paid!(@instrument)
    perform_enqueued_jobs { @reconciler.call }
    assert @instrument.reload.state_paid?
    assert_predicate @bill.reload, :paid?
    assert_not_nil @instrument.reconciled_at

    quiet = emit(@alfa, @bill.customer, "pix", 1_000, reference: nil)
    quiet.update_columns(issued_at: 4.days.ago)
    perform_enqueued_jobs { @reconciler.call }
    assert quiet.reload.state_active?
    assert_operator quiet.reconciled_at, :>, 1.minute.ago
    assert_empty @reconciler.due.to_a
  end

  test "falha do fornecedor em um instrumento não derruba a execução: conta como falha e fica para o dia seguinte" do
    @instrument.update_columns(issued_at: 4.days.ago)
    Payments::Providers::Fake.fail_on(:fetch, Payments::Providers::NetworkError.new("fora do ar"), times: 1)
    perform_enqueued_jobs { @run = @reconciler.call }
    assert_equal 1, @run.reload.failed
    assert_nil @instrument.reload.reconciled_at
    assert_equal [ @instrument ], @reconciler.due.to_a
  end

  test "a conciliação reprocessa os avisos que falharam do credor e só os dele" do
    event = stored_event(@instrument)
    event.update_columns(state: "failed")
    beta = tenants(:beta)
    make_channel(beta, code: "BETA-2")
    other_customer = make_customer(beta, document: PaymentsHelper::JOAO, name: "João")
    other = emit(beta, other_customer, "boleto", 1_000)
    foreign = stored_event(other)
    foreign.update_columns(state: "failed")
    run = nil
    assert_enqueued_jobs(1, only: ProcessPaymentEventJob) { run = @reconciler.call }
    assert_equal "received", event.reload.state
    assert_equal "failed", foreign.reload.state
    assert_match(/reprocessados: 1/, run.note)
  end

  test "a tarefa diária enfileira um credor por vez, só os que têm conta de pagamento" do
    assert_enqueued_with(job: PaymentReconciliationJob, args: [ @alfa ]) { PaymentReconciliationDispatchJob.perform_now }
    assert_equal 1, enqueued_jobs.count { |job| job["job_class"] == "PaymentReconciliationJob" }
  end

  test "agendada todo dia às 7h20, depois do aviso de certificado" do
    schedule = YAML.load_file(Rails.root.join("config/schedule.yml"))
    assert_equal [ "20 7 * * *", "PaymentReconciliationDispatchJob" ], schedule.fetch("payment_reconciliation").values_at("cron", "class")
  end

  test "execução que falha vira TaskRun failed sem derrubar o job" do
    original = Payments::EventReprocessor.method(:new)
    Payments::EventReprocessor.define_singleton_method(:new) { |*| raise "quebrou" }
    run = @reconciler.call
    assert_equal [ "failed", "RuntimeError" ], run.values_at(:status, :error_kind)
  ensure
    Payments::EventReprocessor.define_singleton_method(:new, original)
  end
end
