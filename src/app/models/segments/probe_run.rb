module Segments
  # "Conferir" em segundo plano (13, R288, revisão 3): guarda o pedido, calcula no job e avisa a tela pelo WebSocket. Nada é gravado no banco.
  module ProbeRun
    TTL = 30.minutes

    module_function

    def key(id) = "segments-probe:#{id}"

    def start(tenant, expression)
      id = SecureRandom.uuid
      Rails.cache.write(key(id), { "status" => "running", "tenant_id" => tenant.id, "tree" => expression.tree }, expires_in: TTL)
      SegmentProbeJob.perform_later(id)
      id
    end

    def fetch(id) = Rails.cache.read(key(id))

    def compute(id)
      data = fetch(id) or return
      tenant = Tenant.find(data["tenant_id"])
      result = Probe.new(tenant, Expression.new(data["tree"])).call
      Rails.cache.write(key(id), data.merge("status" => "done").merge(result.deep_stringify_keys), expires_in: TTL)
      Tiers::Broadcast.probe_ready(tenant)
    end
  end
end
