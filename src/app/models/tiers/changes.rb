module Tiers
  # O que uma proposta muda no enquadramento, para a conferência (13, R291, parte 2): item incluído, tirado ou movido, segmento com o texto curto
  # e por extenso antes e depois, regra alterada e parâmetro do credor alterado. Cada mudança diz o que era e o que fica, em texto (não só por cor).
  module Changes
    module_function

    def describe(before, after)
      list = []
      old = before.entries.index_by { |entry| entry[:id] }
      order_before = before.entries.select { |entry| entry[:active] }.map { |entry| entry[:id] }
      order_after = after.entries.select { |entry| entry[:active] }.map { |entry| entry[:id] }
      after.entries.each do |entry|
        was = old[entry[:id]]
        if was.nil?
          list << { "what" => "Incluído no enquadramento: #{entry[:name]}", "before" => nil, "after" => text(after.tenant, entry[:expression]) }
        elsif was[:active] && !entry[:active]
          list << { "what" => "Sai do enquadramento: #{entry[:name]}", "before" => text(after.tenant, was[:expression]), "after" => nil }
        else
          list << { "what" => "Condições de #{entry[:name]}", "before" => text(after.tenant, was[:expression]), "after" => text(after.tenant, entry[:expression]) } if was[:expression] != entry[:expression]
          Tier::RULE_FIELDS.each do |field|
            next if was[field].to_s == entry[field].to_s

            list << { "what" => "#{entry[:name]}: #{I18n.t("tiers.fields.#{field}", default: field.to_s.humanize)}", "before" => { "short" => was[field].to_s.presence || "herda do credor" }, "after" => { "short" => entry[field].to_s.presence || "herda do credor" } }
          end
        end
      end
      list << { "what" => "Ordem do enquadramento", "before" => { "short" => names(before, order_before) }, "after" => { "short" => names(after, order_after) } } if (order_before & order_after) != (order_after & order_before) && (order_before - order_after).empty? && (order_after - order_before).empty?
      after.charges.each do |name, value|
        next if before.charges[name].to_s == value.to_s

        list << { "what" => "Encargos do credor: #{I18n.t("tiers.fields.#{name}", default: name.humanize)}", "before" => { "short" => before.charges[name].to_s }, "after" => { "short" => value.to_s } }
      end
      list
    end

    def text(tenant, tree)
      return nil if tree.blank?

      reading = Segments::Text.new(Segments::Expression.new(tree))
      { "short" => reading.short_text, "long" => reading.long_text }
    end

    def names(proposal, ids) = ids.map { |id| proposal.name_of(id) }.join(" → ")
  end
end
