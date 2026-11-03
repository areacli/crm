module Indexes
  # Evento de invalidação da tela de índices (decisão 0020, sem polling): a busca terminou, a tela refaz o trecho.
  module Broadcast
    module_function

    # Os índices são de todos os credores: a SPA (decisão 0025) recebe o aviso pelo recurso "credores" de cada um.
    def changed
      IndexesChannel.broadcast_to("all", { event: "indexes-changed" })
      Tenant.pluck(:id).each { |id| Live.publish("credores", id, tenant_id: id) }
    end
  end
end
