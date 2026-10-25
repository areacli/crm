# Confirmação da importação em segundo plano (R10), na fila `imports`: uma transação só, que desfaz tudo se falhar.
class ConfirmImportJob < ApplicationJob
  queue_as :imports
  discard_on ActiveJob::DeserializationError

  def perform(import)
    import.confirmer.run(import)
  end
end
