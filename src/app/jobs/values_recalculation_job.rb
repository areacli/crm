# Recálculo do valor atualizado de um credor (09, R173): em segundo plano, depois de confirmar carga, pagamentos, estornos, mudança de encargos
# ou correção de índice, e todo dia depois do recálculo dos segmentos. `run` é o registro já aberto por `Charges::Recalculation.start`.
class ValuesRecalculationJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(tenant, run = nil, import = nil)
    result = Charges::Recalculation.new(tenant).call(run)
    Charges::SurchargeComparison.after(import) if import && result&.succeeded?
  end

  # Abre o registro (para a tela dizer "valores sendo recalculados") e enfileira.
  def self.enqueue_for(tenant, reason: nil, import: nil)
    run = Charges::Recalculation.start(tenant, reason: reason)
    perform_later(tenant, run, import)
  end
end
