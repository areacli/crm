# Confirmação da importação em segundo plano (R10), na fila `imports`: uma transação só, que desfaz tudo se falhar.
class ConfirmImportJob < ApplicationJob
  queue_as :imports
  discard_on ActiveJob::DeserializationError

  def perform(import)
    import.confirmer.run(import)
    # Os segmentos mudam alguns segundos depois da confirmação (R153): o recálculo fica fora do tempo da confirmação, que já é longo com 200 mil linhas.
    SegmentsRecalculationJob.perform_later(import.tenant) if import.reload.confirmed? && import.portfolio?
  end
end
