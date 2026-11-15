module Cadences
  # Conferência do impacto da régua (21, R442), em segundo plano: o que a próxima rodada da agenda faria com a mudança e os dados de agora, por raia,
  # coluna e ação, com quem entra pela primeira coluna e quem entra no meio. Guardada no cache pela assinatura e avisada pelo WebSocket.
  module Review
    module_function

    def key(token) = "cadence-review:#{Digest::SHA256.hexdigest(token)}"
    def read(token) = Rails.cache.read(key(token))

    def compute(tenant, token)
      cadence = Cadence.find_by!(id: Proposal.verifier.verify(token)["cadence_id"], tenant_id: tenant.id)
      proposal = Proposal.from_token(cadence, token)
      raise Refused, I18n.t("cadences.errors.stale") if proposal.stale?

      result = Operations::Context.system do
        Simulation.run(cadence, prepare: ->(record) { Editor.new(record, actor: nil).apply!(proposal.operations) })
      end
      Rails.cache.write(key(token), serialize(result), expires_in: 30.minutes)
    end

    def serialize(result)
      { "slot" => result.slot&.iso8601, "rows" => result.rows, "summary" => result.summary, "commands" => result.commands, "first_column" => result.first_column,
        "middle" => result.middle, "skipped" => result.skipped, "deprioritized" => result.deprioritized, "finished_at" => Time.current.iso8601 }
    end
  end
end
