# Recálculo do segmento dos contratos de um credor (08, R153): diário, depois de confirmar uma carga e de confirmar mudança de segmentos.
class SegmentsRecalculationJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  # Os valores atualizados dependem do segmento do contrato: o recálculo deles vem logo depois (09, R173). `import` é a carga que o pediu, para a
  # comparação dos acréscimos "depois de confirmar" (R182).
  def perform(tenant, import = nil)
    Segments::Recalculation.new(tenant).call
    ValuesRecalculationJob.enqueue_for(tenant, reason: import ? "carga" : "diário", import: import)
  end
end
