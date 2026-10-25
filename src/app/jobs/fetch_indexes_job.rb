# Busca dos índices no Banco Central (08, R142), global do sistema: agendada às 5h e chamada por "Buscar índices agora". Tenta de novo 3 vezes
# (a cada 5 minutos) quando o Banco Central falha; depois da última, a falha fica na tela e o job termina sem repetir (R144).
class FetchIndexesJob < ApplicationJob
  queue_as :default
  retry_on(Indexes::Fetch::Failed, wait: 5.minutes, attempts: 3) { |_job, _error| nil }

  def perform = Indexes::Fetch.new.call
end
