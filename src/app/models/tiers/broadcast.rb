module Tiers
  # Eventos de invalidação da configuração de segmentos e enquadramento de um credor (decisão 0020, sem polling): o recálculo terminou, uma
  # conferência do impacto ficou pronta, um "Conferir" do editor ficou pronto.
  module Broadcast
    module_function

    def changed(tenant) = SegmentsChannel.broadcast_to(tenant, { event: "segments-changed" })
    def review_ready(tenant) = SegmentsChannel.broadcast_to(tenant, { event: "tier-review-ready" })
    def probe_ready(tenant) = SegmentsChannel.broadcast_to(tenant, { event: "segment-probe-ready" })
  end
end
