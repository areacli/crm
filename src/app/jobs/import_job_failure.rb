# Retomada e falha dos jobs de importação (decisão 0021). Os jobs são `ActiveJob::Continuable`: uma interrupção (reinício do contêiner) ou um erro
# depois de o cursor avançar retoma do cursor. Falha passageira do banco tenta de novo; qualquer outra falha, ou a tentativa que se esgota, deixa a
# importação "falhou", com o tipo do erro em `failure_reason`, e libera o credor para uma nova carga.
module ImportJobFailure
  extend ActiveSupport::Concern

  included do
    include ActiveJob::Continuable

    rescue_from(StandardError) { |error| fail_import(error) }
    retry_on(ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, ActiveRecord::ConnectionFailed, wait: 10.seconds, attempts: 5) { |job, error| job.fail_import(error) }
  end

  def fail_import(error)
    import = arguments.first.reload
    (is_a?(CheckImportJob) ? import.checker : import.confirmer).fail!(import, error)
  end
end
