# Recálculo do segmento dos contratos de um credor (08, R153): diário, depois de confirmar uma carga e de confirmar mudança de segmentos.
class SegmentsRecalculationJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(tenant) = Segments::Recalculation.new(tenant).call
end
