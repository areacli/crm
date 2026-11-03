module Titular
  # Evento de invalidação da página de guarda (decisão 0020, sem polling): a mudança vai ao canal do credor e a tela refaz o trecho.
  module Broadcast
    module_function

    def changed(tenant) = RetentionChannel.broadcast_to(tenant, { event: "retention-changed" })
  end
end
