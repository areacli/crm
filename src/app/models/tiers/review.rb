module Tiers
  # Conferência do impacto em segundo plano (13, R272, revisão 3): a tela abre com "Conferindo…" e o resultado aparece quando o cálculo termina,
  # avisado pelo WebSocket (sem polling). O resultado fica guardado por 35 minutos (a proposta assinada vale 30), já com os nomes e os valores
  # que a tela mostra; a confirmação usa a proposta assinada, nunca o que está guardado aqui.
  module Review
    TTL = 35.minutes

    module_function

    def key(id) = "tiers-review:#{id}"

    # Guarda a conferência pedida e enfileira o cálculo; devolve o identificador.
    def start(proposal, back:, changes:)
      id = SecureRandom.uuid
      Rails.cache.write(key(id), { "status" => "running", "tenant_id" => proposal.tenant.id, "token" => proposal.token, "back" => back, "changes" => changes }, expires_in: TTL)
      TierReviewJob.perform_later(id)
      id
    end

    def fetch(id) = Rails.cache.read(key(id))

    # O cálculo (o job chama): impacto por item e de onde para onde, contratos mistos, valor atualizado antes e depois e os avisos do CDC.
    def compute(id)
      data = fetch(id) or return
      tenant = Tenant.find(data["tenant_id"])
      proposal = Proposal.from_token(tenant, data["token"])
      impact = Impact.new(proposal)
      charges = Charges::Impact.new(proposal)
      result = data.merge("status" => "done", "finished_at" => Time.current.iso8601,
                          "total" => impact.total, "balance_cents" => impact.balance_cents, "mixed" => impact.mixed,
                          "items" => items(proposal, impact), "moves" => impact.rows.sort_by { |row| -row.contracts }.map { |row| { "from" => proposal.name_of(row.from_id), "to" => proposal.name_of(row.to_id), "contracts" => row.contracts, "balance_cents" => row.balance_cents } },
                          "values" => charges.changes_values? ? charges.rows.map { |row| { "name" => row.name, "customers" => row.customers, "before" => row.before_cents, "after" => row.after_cents } } : nil,
                          "cdc" => charges.cdc_warnings)
      Rails.cache.write(key(id), result, expires_in: TTL)
      Broadcast.review_ready(tenant)
      result
    rescue Refused => error
      Rails.cache.write(key(id), data.merge("status" => "failed", "error" => error.message), expires_in: TTL)
      Broadcast.review_ready(tenant)
    end

    # Por item, na ordem da proposta: contratos e saldo que entram e saem (R291, parte 3).
    def items(proposal, impact)
      entering = impact.entering
      leaving = impact.leaving
      proposal.entries.select { |entry| entry[:active] || entry[:catch_all] }.map do |entry|
        id = entry[:id]
        { "name" => entry[:name], "in" => entering.fetch(id, []).sum(&:contracts), "in_cents" => entering.fetch(id, []).sum(&:balance_cents),
          "out" => leaving.fetch(id, []).sum(&:contracts), "out_cents" => leaving.fetch(id, []).sum(&:balance_cents) }
      end + removed(proposal, leaving)
    end

    def removed(proposal, leaving)
      proposal.entries.reject { |entry| entry[:active] || entry[:catch_all] }.filter_map do |entry|
        rows = leaving.fetch(entry[:id], [])
        next if rows.empty?

        { "name" => "#{entry[:name]} (sai do enquadramento)", "in" => 0, "in_cents" => 0, "out" => rows.sum(&:contracts), "out_cents" => rows.sum(&:balance_cents) }
      end
    end
  end
end
