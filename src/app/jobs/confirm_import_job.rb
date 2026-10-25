# Confirmação da importação em segundo plano (R10), na fila `imports`: uma transação só, que desfaz tudo se falhar.
class ConfirmImportJob < ApplicationJob
  queue_as :imports
  discard_on ActiveJob::DeserializationError

  def perform(import)
    import.confirmer.run(import)
    # Os segmentos mudam alguns segundos depois da confirmação (R153): o recálculo fica fora do tempo da confirmação, que já é longo com 200 mil linhas.
    return unless import.reload.confirmed?

    if import.portfolio?
      SegmentsRecalculationJob.perform_later(import.tenant, import)
    else
      # Pagamentos e estornos mudam o principal em aberto e os encargos pagos (09, R173).
      ValuesRecalculationJob.enqueue_for(import.tenant, reason: "pagamentos")
    end
  end
end
