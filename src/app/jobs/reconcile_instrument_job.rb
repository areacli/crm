# Confere um instrumento ativo no fornecedor (12, parte D, conciliação). Falha do fornecedor não derruba a conciliação: conta na execução, relata e deixa
# o instrumento para a próxima (a data da última conferência só avança quando a consulta deu certo).
class ReconcileInstrumentJob < ApplicationJob
  queue_as :webhooks
  discard_on ActiveJob::DeserializationError

  def perform(instrument, run = nil)
    Payments::InstrumentSync.new.call(instrument)
  rescue Payments::Providers::Error => error
    TaskRun.update_counters(run.id, failed: 1) if run
    Rails.error.report(error, handled: true, context: { payment_instrument_id: instrument.id })
  end
end
