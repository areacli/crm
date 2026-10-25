# Busca dos índices no Banco Central (08, R142), global do sistema: agendada às 5h e chamada por "Buscar índices agora". Tenta de novo 3 vezes
# (a cada 5 minutos) quando o Banco Central falha; depois da última, a falha fica na tela e o job termina sem repetir (R144).
class FetchIndexesJob < ApplicationJob
  queue_as :default
  retry_on(Indexes::Fetch::Failed, wait: 5.minutes, attempts: 3) { |_job, _error| nil }

  # `recalculate`: na busca manual, os valores atualizados de todos os credores são recalculados depois (09, R173); a diária já tem o recálculo
  # encadeado ao dos segmentos.
  def perform(recalculate = false)
    Indexes::Fetch.new.call
    ValuesDispatchJob.perform_later if recalculate
  end
end
