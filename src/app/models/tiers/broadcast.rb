module Tiers
  # Eventos de invalidação da configuração de segmentos e enquadramento de um credor (decisão 0020, sem polling): o recálculo terminou, uma
  # conferência do impacto ficou pronta, um "Conferir" do editor ficou pronto.
  module Broadcast
    module_function

    # Cada evento vai também à SPA (decisão 0025), pelo recurso "credores" do tempo real.
    def changed(tenant) = avisar(tenant, "segments-changed")
    def review_ready(tenant) = avisar(tenant, "tier-review-ready")
    def probe_ready(tenant) = avisar(tenant, "segment-probe-ready")

    def avisar(tenant, event)
      SegmentsChannel.broadcast_to(tenant, { event: event })
      Live.publish("credores", tenant.id, tenant_id: tenant.id)
    end
  end
end
