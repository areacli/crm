module Payments
  # Confirmação da importação de pagamentos ou de estornos: aplica tudo numa única transação (R56, R63), com o mesmo bloqueio por credor
  # da carteira. Nada é gravado se qualquer passo falhar.
  class ImportConfirmer
    Sql = Portfolio::Sql

    def run(import)
      import.update!(status: :confirming, progress_percent: 1, progress_label: "Gravando")
      begin
        effect = ApplicationRecord.transaction do
          # Uma importação por vez por credor (R10): o mesmo bloqueio consultivo da carteira.
          Sql.execute("select pg_advisory_xact_lock(1, ?)", import.tenant_id)
          import.reversals? ? ReversalProcessor.new.run(import, commit: true) : Processor.new.run(import, commit: true)
        end
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: { import_id: import.id })
        import.update!(status: :failed, failure_reason: error.class.name.demodulize, finished_at: Time.current, progress_label: nil)
        return
      end
      # Carga em massa deixa as estatísticas defasadas: sem isto, a primeira consulta depois da carga pega um plano ruim.
      %w[payments credits bills payment_reversals].each { |table| Sql.connection.execute("analyze #{table}") }
      Sql.run("delete from payment_rows where import_id = ?", import.id)
      FileUtils.rm_f(import.file_path) if import.stored_path
      summary = import.summary_data.merge(confirmed_effect: effect)
      import.update!(status: :confirmed, summary: summary, progress_percent: 100, progress_label: nil, finished_at: Time.current)
    end
  end
end
