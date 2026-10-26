# Confirmação da importação em segundo plano (R10), na fila `imports`, em lotes e etapas retomáveis (decisão 0021): cada lote é uma transação, o cursor
# avança junto com o commit e a importação só vira "confirmada" no fim. A carteira grava clientes inteiros; pagamentos e estornos gravam lotes de
# linhas na ordem do fluxo.
class ConfirmImportJob < ApplicationJob
  include ImportJobFailure

  queue_as :imports
  discard_on ActiveJob::DeserializationError

  def perform(import)
    import.confirmer.run(import, self)
    # O que depende do que a confirmação gravou fica fora do tempo dela, que já é longo com 200 mil linhas.
    step(:recalculate) { follow_up(import.reload) }
  end

  private
    def follow_up(import)
      return unless import.confirmed?

      if import.portfolio?
        # Os segmentos mudam alguns segundos depois da confirmação (R153).
        SegmentsRecalculationJob.perform_later(import.tenant, import)
      else
        # Pagamentos e estornos mudam o principal em aberto e os encargos pagos (09, R173).
        ValuesRecalculationJob.enqueue_for(import.tenant, reason: "pagamentos")
      end
    end
end
