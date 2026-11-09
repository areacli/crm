module Queues
  # Conferência do impacto de uma mudança do enquadramento da fila (15, R357; 13, R272), em segundo plano: por item, quantos sujeitos entram e
  # saem e de onde vêm. Guardada no cache pela assinatura da proposta e avisada pelo WebSocket.
  module Review
    module_function

    def key(token) = "queue-review:#{Digest::SHA256.hexdigest(token)}"

    def read(token) = Rails.cache.read(key(token))

    def compute(tenant, token)
      proposal = Proposal.from_token(tenant, token)
      current = Proposal.current(tenant, proposal.subject)
      Operations::Context.system do
        before = assignment(tenant, current)
        after = assignment(tenant, proposal)
        moves = Hash.new(0)
        after.each { |id, name| moves[[ before[id], name ]] += 1 if before[id] != name }
        rows = moves.map { |(from, to), count| { "from" => from, "to" => to, "count" => count } }.sort_by { |row| -row["count"] }
        Rails.cache.write(key(token), { "rows" => rows, "total" => rows.sum { _1["count"] }, "finished_at" => Time.current.iso8601 }, expires_in: 30.minutes)
      end
    end

    # { sujeito => nome do item (ou "Demais" / "sem fila") }.
    def assignment(tenant, proposal)
      catch_all = WorkQueue.catch_all_for(tenant, proposal.subject)
      segments = Segment.where(id: proposal.items.map(&:segment_id)).index_by(&:id)
      entries = proposal.items.each_with_index.map { |item, index| [ index + 1, segments.fetch(item.segment_id).expression_object ] }
      names = proposal.items.each_with_index.to_h { |item, index| [ index + 1, item.delivers ? item.name : "#{item.name} (sem fila)" ] }
      names[0] = catch_all.delivers ? catch_all.name : "#{catch_all.name} (sem fila)"
      query = Segments::Compiler.new(tenant).classify_subjects(proposal.subject, entries, default_id: 0)
      Segments::Compiler.select(query).to_h { |row| [ row["subject_id"].to_i, names[row["item_id"].to_i] ] }
    end
  end
end
