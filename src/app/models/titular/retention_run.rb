module Titular
  # Tarefa diária de guarda de um credor (07, R137, R137a): anonimiza quem passou do prazo e não está retido, em lotes; se um lote falha, refaz
  # um a um, de modo que a falha de um cliente fica registrada e não para os outros. Cada execução vira um `TaskRun` do credor (O8).
  class RetentionRun
    NAME = "data_retention".freeze
    BATCH = 200

    def initialize(tenant) = @tenant = tenant

    def call(today: Date.current)
      run = TaskRun.create!(tenant: @tenant, name: NAME, started_at: Time.current)
      if Import.in_progress.exists?(tenant_id: @tenant.id)
        run.update!(status: :skipped, finished_at: Time.current, note: I18n.t("titular.run.import_running"))
      else
        processed, failed, kind = anonymize_due(today)
        run.update!(status: failed.zero? ? :succeeded : :failed, finished_at: Time.current, processed: processed, failed: failed, error_kind: kind)
      end
      run
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { tenant_id: @tenant.id })
      run&.update!(status: :failed, finished_at: Time.current, error_kind: error.class.name.demodulize)
      run
    ensure
      Broadcast.changed(@tenant)
    end

    private
      def anonymize_due(today)
        ids = Retention.due([ @tenant.id ], today: today).pluck(:id)
        processed = failed = 0
        kind = nil
        ids.each_slice(BATCH) do |slice|
          processed += Anonymizer.in_batch(@tenant.id, slice)
        rescue StandardError
          slice.each do |id|
            processed += Anonymizer.in_batch(@tenant.id, [ id ])
          rescue StandardError => error
            failed += 1
            kind ||= error.class.name.demodulize
            Rails.error.report(error, handled: true, context: { tenant_id: @tenant.id, customer_id: id })
          end
        end
        [ processed, failed, kind ]
      end
  end
end
