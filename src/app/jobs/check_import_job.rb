# Conferência da importação em segundo plano (R10), na fila `imports`. É idempotente: se o contêiner reiniciar no meio, a conferência
# recomeça do zero (a tabela de preparação é limpa antes). Não usa `ActiveJob::Continuable`: o trabalho todo é uma sequência de
# operações em lote no banco, que não se retomam pela metade.
class CheckImportJob < ApplicationJob
  queue_as :imports
  discard_on ActiveJob::DeserializationError

  def perform(import)
    import.checker.run(import)
  end
end
