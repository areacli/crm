module Segments
  # A conferência única do segmento (13, R272, revisão 8; 21, R443): além dos itens do enquadramento financeiro (`Tiers::Review`), o efeito da
  # mudança nos outros processos que usam o segmento: quantos entram e saem de cada item da distribuição e das filas, e quantos comandos a próxima
  # rodada de cada régua ligada passaria a ter. Tudo calculado com a mudança aplicada numa transação desfeita no fim.
  module Impact
    module_function

    # `changes`: { id do segmento => { "expression", "active", "name" } }, como na proposta do financeiro. Devolve [{ process, item, before, after }].
    def others(tenant, changes)
      ids = changes.keys.map(&:to_i)
      return [] if ids.empty?

      Operations::Context.system { distribution(tenant, ids, changes) + queues(tenant, ids, changes) + cadences(tenant, ids, changes) }
    end

    def apply(tenant, changes)
      changes.each do |id, change|
        Segment.where(id: id, tenant_id: tenant.id).update_all(change.slice("expression", "active").merge("updated_at" => Time.current))
      end
    end

    # Conta antes e depois, com a mudança aplicada só dentro do bloco.
    def before_and_after(tenant, changes)
      before = yield
      after = nil
      ApplicationRecord.transaction(requires_new: true) do
        apply(tenant, changes)
        after = yield
        raise ActiveRecord::Rollback
      end
      [ before, after ]
    end

    def distribution(tenant, ids, changes)
      items = DistributionRuleItem.where(tenant: tenant, active: true).ordered.includes(:segment).to_a
      return [] unless items.any? { |item| ids.include?(item.segment_id) }

      count = lambda do
        entries = items.map { |item| [ item.id, Segment.find(item.segment_id).expression_object ] }
        Segments::Compiler.select(Segments::Compiler.new(tenant).classify(entries, default_id: 0)).group_by { |row| row["tier_id"].to_i }.transform_values(&:size)
      end
      before, after = before_and_after(tenant, changes, &count)
      rows("distribution", items.to_h { |item| [ item.id, item.segment.name ] }.merge(0 => I18n.t("segments.impact.team")), before, after)
    end

    def queues(tenant, ids, changes)
      WorkQueue::SUBJECTS.flat_map do |subject|
        framing = WorkQueue.framing(tenant, subject)
        next [] unless framing.any? { |queue| ids.include?(queue.segment_id) }

        catch_all = framing.find(&:catch_all)
        count = lambda do
          entries = framing.reject(&:catch_all).select { |queue| queue.segment && Segment.find(queue.segment_id).active? }
                           .map { |queue| [ queue.id, Segment.find(queue.segment_id).expression_object ] }
          Segments::Compiler.select(Segments::Compiler.new(tenant).classify_subjects(subject, entries, default_id: catch_all.id))
                            .group_by { |row| row["item_id"].to_i }.transform_values(&:size)
        end
        before, after = before_and_after(tenant, changes, &count)
        rows("queues", framing.to_h { |queue| [ queue.id, queue.name ] }, before, after)
      end
    end

    # A próxima rodada de cada régua ligada que usa o segmento (R443), em comandos.
    def cadences(tenant, ids, changes)
      Cadence.where(tenant: tenant, enabled: true).joins(:lanes).where(cadence_lanes: { segment_id: ids, removed_at: nil }).distinct.by_priority.filter_map do |cadence|
        before = Cadences::Simulation.run(cadence)
        after = Cadences::Simulation.run(cadence, slot: before.slot, prepare: ->(_) { apply(tenant, changes) })
        { "process" => "cadences", "item" => cadence.name, "before" => before.commands, "after" => after.commands } if before.commands != after.commands
      end
    end

    def rows(process, names, before, after)
      (before.keys | after.keys).filter_map do |id|
        old = before.fetch(id, 0)
        new = after.fetch(id, 0)
        { "process" => process, "item" => names.fetch(id, "?"), "before" => old, "after" => new } if old != new
      end
    end
  end
end
