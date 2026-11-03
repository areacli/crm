module Queues
  # Evento pequeno de invalidação (decisão 0020): quem tem a visão das filas ou a configuração aberta busca o trecho de novo.
  module Broadcast
    module_function

    def changed(tenant) = QueuesChannel.broadcast_to(tenant, { event: "queues-changed" })
  end
end
