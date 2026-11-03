module Queues
  # Reavaliação sem trava de alguns sujeitos (15, R351): o item do enquadramento em que cada um casa agora, e a fila gravada trocada se mudou.
  # O "Próximo" a usa para o candidato; o recálculo completo continua com a `Recalculation`.
  module Placer
    module_function

    # Devolve { subject_id => work_queue_id (nil = sem fila) } e grava as mudanças.
    # `framing`: o enquadramento já montado (o "Próximo" o monta uma vez por pedido; montá-lo custa uns 15 ms, medição da V4).
    def reevaluate(tenant, subject, ids, framing: nil)
      framing ||= WorkQueue.framing(tenant, subject)
      catch_all = framing.find(&:catch_all)
      entries = framing.reject(&:catch_all).select { |queue| queue.segment&.active? }.map { |queue| [ queue.id, queue.segment.expression_object ] }
      query = Segments::Compiler.new(tenant).classify_subjects(subject, entries, default_id: catch_all.id, only_ids: ids)
      delivering = framing.select(&:delivers).map(&:id)
      found = Segments::Compiler.select(query).to_h { |row| [ row["subject_id"].to_i, delivering.include?(row["item_id"].to_i) ? row["item_id"].to_i : nil ] }
      QueuePlacement.where(subject: subject, subject_id: found.keys).find_each do |placement|
        target = found[placement.subject_id]
        next if placement.work_queue_id == target

        rank = target ? QueuePlacement.where(work_queue_id: target).maximum(:rank).to_i + 1 : 0
        placement.update!(work_queue_id: target, rank: rank)
      end
      found
    end
  end
end
