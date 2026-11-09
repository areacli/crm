module DistributionRules
  # Conferência do impacto de uma mudança do enquadramento da distribuição (14, R345), em segundo plano: por operação, quantos contratos e
  # quanto saldo entram e saem; os contratos com distribuição à mão ficam de fora (R344). Guardada no cache pela assinatura da proposta.
  module Review
    module_function

    def key(token) = "distribution-review:#{Digest::SHA256.hexdigest(token)}"

    def read(token) = Rails.cache.read(key(token))

    def compute(tenant, token)
      proposal = Proposal.from_token(tenant, token)
      current = Proposal.current(tenant)
      Operations::Context.system do
        ApplicationRecord.transaction do
          Assignment.load(tenant, keyed(current), table: "dist_now")
          Assignment.load(tenant, keyed(proposal), table: "dist_new")
          rows = ActiveRecord::Base.connection.select_rows(<<~SQL)
            select n.item_key, w.item_key, count(*), coalesce(sum(n.balance_cents), 0) from dist_now n join dist_new w using (contract_id)
             where not exists (select 1 from distributions d where d.tenant_id = #{tenant.id.to_i} and d.contract_id = n.contract_id and d.source <> 'rule' and d.ended_at is null)
             group by 1, 2
          SQL
          Rails.cache.write(key(token), summarize(rows, current, proposal, tenant), expires_in: 30.minutes)
        end
      end
    end

    def keyed(proposal) = proposal.items.each_with_index.map { |item, index| [ index + 1, Segment.find(item.segment_id).expression_object ] }

    def summarize(rows, current, proposal, tenant)
      names = Operation.where(id: (current.items + proposal.items).flat_map(&:operation_ids)).pluck(:id, :short_name).to_h
      ops = ->(plan, key) { key.to_i.zero? ? [] : plan.items[key.to_i - 1].operation_ids }
      moves = Hash.new { |hash, name| hash[name] = { "in" => 0, "out" => 0, "in_cents" => 0, "out_cents" => 0 } }
      rows.each do |old_key, new_key, count, cents|
        before = ops.call(current, old_key)
        after = ops.call(proposal, new_key)
        (after - before).each { |id| moves[names[id]]["in"] += count.to_i; moves[names[id]]["in_cents"] += cents.to_i }
        (before - after).each { |id| moves[names[id]]["out"] += count.to_i; moves[names[id]]["out_cents"] += cents.to_i }
        if before.empty? ^ after.empty?
          team = after.empty? ? "in" : "out"
          moves["Equipe do credor"][team] += count.to_i
          moves["Equipe do credor"]["#{team}_cents"] += cents.to_i
        end
      end
      { "moves" => moves.sort.to_h, "total" => moves.values.sum { |move| move["in"] }, "tenant_id" => tenant.id, "finished_at" => Time.current.iso8601 }
    end
  end
end
