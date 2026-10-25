module Indexes
  # Evento de invalidação da tela de índices (decisão 0020, sem polling): a busca terminou, a tela refaz o trecho.
  module Broadcast
    module_function

    def changed = IndexesChannel.broadcast_to("all", { event: "indexes-changed" })
  end
end
