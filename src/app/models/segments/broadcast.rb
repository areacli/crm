module Segments
  # Evento de invalidação da aba Segmentos de um credor (decisão 0020, sem polling).
  module Broadcast
    module_function

    def changed(tenant) = SegmentsChannel.broadcast_to(tenant, { event: "segments-changed" })
  end
end
