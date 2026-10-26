module Payments
  # Confirmação da importação de pagamentos ou de estornos (R56, R63): grava em lotes, em segundo plano (decisão 0021). Cada lote é uma transação travada
  # pelo bloqueio por credor, o cursor fica gravado na mesma transação (`imports.batch_state`) e a importação só vira "confirmada" no fim. Etapas retomáveis
  # (`ActiveJob::Continuable`): preparar, ordenar o fluxo, aplicar os lotes, concluir. A baixa de cada pagamento é idempotente por canal e identificador
  # (R48): se um lote falhar de vez, o que os lotes anteriores gravaram fica, e enviar o mesmo arquivo de novo ignora o já registrado e conclui o resto.
  class ImportConfirmer
    # `runner` roda as etapas: o job (com cursor e retomada) ou o `InlineRunner` (seguido, na mesma chamada).
    def run(import, runner = Portfolio::InlineRunner)
      runner.step(:prepare) { prepare(import) }
      runner.step(:order) { PaymentStream.prepare(import) }
      runner.step(:apply) { |step| apply(import, step) }
      runner.step(:finish) { finish(import) }
    end

    # Falha definitiva: o que os lotes já gravaram fica; a importação fica como falha e libera o credor.
    def fail!(import, error)
      Rails.error.report(error, handled: true, context: { import_id: import.id })
      PaymentRow.where(import_id: import.id).delete_all
      import.update!(status: :failed, failure_reason: error.class.name.demodulize, finished_at: Time.current, progress_label: nil)
    end

    private
      def prepare(import)
        import.update!(status: :confirming, progress_percent: 1, progress_label: "Gravando")
        import.update_columns(batch_state: nil)
      end

      def apply(import, step)
        import.update!(progress_percent: 10, progress_label: "Gravando")
        import.reversals? ? ReversalProcessor.new.run(import, commit: true, step: step) : Processor.new.run(import, commit: true, step: step)
      end

      def finish(import)
        effect = import.reload.batch_state&.fetch("effect", nil) || {}
        # Carga em massa deixa as estatísticas defasadas: sem isto, a primeira consulta depois da carga pega um plano ruim.
        %w[payments credits bills payment_reversals].each { |table| ActiveRecord::Base.connection.execute("analyze #{table}") }
        PaymentRow.where(import_id: import.id).delete_all
        FileUtils.rm_f(import.file_path) if import.stored_path
        import.update!(status: :confirmed, summary: import.summary_data.merge(confirmed_effect: effect), progress_percent: 100, progress_label: nil, finished_at: Time.current)
      end
  end
end
