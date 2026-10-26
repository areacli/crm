# Conferência da importação em segundo plano (R10), na fila `imports`. Processamento em lote (decisão 0021): a conferência (carteira, pagamentos e estornos)
# roda em etapas retomáveis (`ActiveJob::Continuable`, guia de Active Job Continuations do Rails 8.1), com o cursor na última linha gravada. Reinício do
# contêiner, deploy ou falha passageira retomam do cursor; uma falha que se repete sem avançar marca a importação como falha.
class CheckImportJob < ApplicationJob
  include ImportJobFailure

  queue_as :imports
  discard_on ActiveJob::DeserializationError

  def perform(import)
    import.checker.run(import, self)
  end
end
