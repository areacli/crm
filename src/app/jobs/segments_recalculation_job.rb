# Recálculo do enquadramento dos contratos de um credor (13, R268), do alcance das operações (14, R313) e das filas (15, R351): diário, depois de confirmar uma carga e
# de confirmar mudança do enquadramento.
class SegmentsRecalculationJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  # Os valores atualizados dependem do segmento do contrato: o recálculo deles vem logo depois (09, R173). `import` é a carga que o pediu, para a
  # comparação dos acréscimos "depois de confirmar" (R182).
  def perform(tenant, import = nil)
    Tiers::Recalculation.new(tenant).call
    # O alcance das operações (14, R313; decisão 0024) muda com a carga (quem figura em cada contrato) e com o dia (início e fim das
    # distribuições, corte da exposição "vencidas").
    Distributions::Daily.new(tenant).call
    DistributionRules::Recalculation.new(tenant).apply
    Operations::ReachBuilder.new(tenant).rebuild
    # As filas (15, R351) leem o mesmo dia e o alcance já refeito.
    Queues::Recalculation.new(tenant).call
    ValuesRecalculationJob.enqueue_for(tenant, reason: import ? "carga" : "diário", import: import)
  end
end
