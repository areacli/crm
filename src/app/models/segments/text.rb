module Segments
  # As duas leituras de um segmento (13, R278): o texto curto da linguagem (SG4, SG13, SG14) e a leitura por extenso em português comum, as duas
  # geradas da mesma árvore e do catálogo. Nada aqui lê banco, a não ser o nome dos resultados de acionamento, que a árvore guarda pelo id.
  class Text
    Line = Data.define(:address, :short, :long, :depth)

    def initialize(expression, result_names: nil)
      @expression = expression
      @subject = expression.subject
      @result_names = result_names
    end

    # Linhas na ordem do texto, com o grupo "qualquer:" e as condições dele recuadas.
    def lines
      @lines ||= [ Line.new(nil, t("subjects.#{@subject}.short"), nil, 0) ] + @expression.conditions.each_with_index.reject { |node, _| blank?(node) }.flat_map do |node, index|
        if node.key?("any")
          [ Line.new(index.to_s, t("any_short"), nil, 1) ] +
            Array(node["any"]).each_with_index.reject { |inner, _| blank?(inner) }.map { |inner, inner_index| Line.new("#{index}.#{inner_index}", short(inner), long(inner), 2) }
        else
          [ Line.new(index.to_s, short(node), long(node), 1) ]
        end
      end
    end

    def short_text = lines.map { |line| "#{'  ' * line.depth}#{line.short}" }.join("\n")

    # O segmento inteiro numa frase: "Seleciona contratos em que …; e …".
    def long_text
      parts = @expression.conditions.reject { |node| blank?(node) }.map do |node|
        node.key?("any") ? t("any_long", parts: Array(node["any"]).reject { |inner| blank?(inner) }.map { |inner| long(inner) }.join(t("sentence.or_joiner"))) : long(node)
      end
      return "" if parts.empty?

      t("sentence.whole", subject: t("subjects.#{@subject}.long"), parts: parts.join(t("sentence.joiner")))
    end

    # Texto curto de uma condição: "atraso > 90", "títulos vencidos >= 3", "nenhum acionamento \"Contato efetivo\" em 30 dias".
    def short(node)
      found = Catalog.resolve(@subject, node["path"])
      return node["path"].to_s unless found

      text = found[:kind] == :attribute ? short_attribute(found, node) : short_collection(found, node)
      negated = node["negate"] && found.dig(:spec, :type) != :boolean
      negated ? "#{t('not_short')} #{text}" : text
    end

    # Leitura por extenso de uma condição: "o contrato tem atraso maior que 90 dias".
    def long(node)
      found = Catalog.resolve(@subject, node["path"])
      return node["path"].to_s unless found

      found[:kind] == :attribute ? long_attribute(found, node) : long_collection(found, node)
    end

    private
      # Condição ainda sem caminho escolhido (linha nova do editor) não entra no texto.
      def blank?(node) = !node.is_a?(Hash) || (node.key?("any") ? Array(node["any"]).all? { |inner| blank?(inner) } : node["path"].blank?)

      def t(key, **options) = I18n.t("segment_language.#{key}", **options)

      def owner(found) = found[:parent] ? t("parents.#{found[:parent]}.owner") : t("subjects.#{@subject}.owner")

      def attribute_key(found) = found[:parent] ? "attributes.customers.#{found[:name]}" : "attributes.#{@subject}.#{found[:name]}"

      def short_attribute(found, node)
        label = t("#{attribute_key(found)}.short")
        label = "#{t("parents.#{found[:parent]}.short")} #{label}" if found[:parent]
        return (node["negate"] ? "#{t('not_short')} #{label}" : label) if found[:spec][:type] == :boolean

        "#{label} #{short_comparison(node, found[:spec], found[:name])}"
      end

      def long_attribute(found, node)
        if found[:spec][:type] == :boolean
          return "#{owner(found)} #{t("#{attribute_key(found)}.#{node['negate'] ? 'no' : 'yes'}")}"
        end

        rest = "#{t("#{attribute_key(found)}.long")} #{long_comparison(node, found[:spec], found[:name])}"
        t(node["negate"] ? "sentence.has_not" : "sentence.has", owner: owner(found), rest: rest)
      end

      def short_collection(found, node)
        name = found[:name]
        spec = found[:spec]
        prefix = found[:parent] ? "#{t("parents.#{found[:parent]}.short")} " : ""
        text =
          if node["aggregate"].present?
            items = items_short(name, node, :other)
            if node["aggregate"] == "count"
              "#{items} #{short_comparison(node, { type: :count }, nil)}"
            else
              field = t("fields.#{name}.#{node['field']}")
              "#{t("aggregates.#{node['aggregate']}.short")} #{field} #{items} #{short_comparison(node, spec[:fields].fetch(node['field'].to_sym), node['field'])}"
            end
          else
            quantified(name, spec, node)
          end
        text = "#{prefix}#{text}"
        node["within_days"].present? ? "#{text} #{t('window_short', days: node['within_days'])}" : text
      end

      # "algum título \"Cartão\"", "sem contato válido", "todos os títulos com tipo = acordo" (SG13, SG14: atalho pelo campo principal).
      def quantified(name, spec, node)
        quantifier = node["quantifier"]
        feminine = spec[:gender] == :f
        where = node["where"]
        if quantifier == "none" && where.blank?
          return "#{t('quantifiers.without')} #{items_short(name, node, :one)}"
        end

        number = quantifier == "all" ? :other : :one
        word = t("quantifiers.#{quantifier}.#{feminine ? 'short_f' : 'short'}")
        text = "#{word} #{items_short(name, node, number)}"
        return text if where.blank?

        "#{text} #{where_short(name, spec, where)}"
      end

      def where_short(name, spec, where)
        field = where["field"].to_s
        field_spec = spec[:fields].fetch(field.to_sym)
        if field == spec[:main].to_s && %w[eq in].include?(where["op"])
          Array(where["value"]).map { |value| "\"#{value_short(value, field_spec, field, name)}\"" }.join(", ")
        else
          "com #{t("fields.#{name}.#{field}")} #{short_comparison(where, field_spec, field, name)}"
        end
      end

      def items_short(name, node, number)
        words = [ t("collections.#{name}.#{number}") ]
        words << t("qualifiers.#{name}.#{node['qualifier']}.#{number}") if node["qualifier"].present?
        words.join(" ")
      end

      def long_collection(found, node)
        name = found[:name]
        spec = found[:spec]
        window = node["within_days"].present? ? " #{t('window_long', days: node['within_days'])}" : ""
        if node["aggregate"] == "count"
          number = node["value"] == 1 && %w[eq gte lte].include?(node["op"]) ? :one : :other
          rest = "#{long_count(node)} #{items_long(name, node, number)}#{window}"
          return t(node["negate"] ? "sentence.has_not" : "sentence.has", owner: owner(found), rest: rest)
        end
        if node["aggregate"].present?
          field = t("fields.#{name}.#{node['field']}")
          head = t("aggregates.#{node['aggregate']}.long", field: field)
          rest = "#{head} dos #{items_long(name, node, :other)}#{window} #{long_comparison(node, spec[:fields].fetch(node['field'].to_sym), node['field'], name)}"
          return t(node["negate"] ? "sentence.has_not" : "sentence.has", owner: owner(found), rest: rest)
        end

        where = node["where"].present? ? " #{where_long(name, spec, node['where'])}" : ""
        feminine = spec[:gender] == :f
        case node["quantifier"]
        when "some"
          t(node["negate"] ? "sentence.has_not" : "sentence.has", owner: owner(found),
            rest: "#{t("quantifiers.some.#{feminine ? 'short_f' : 'short'}")} #{items_long(name, node, :one)}#{where}#{window}")
        when "none"
          t(node["negate"] ? "sentence.has" : "sentence.has_not", owner: owner(found),
            rest: "#{t("quantifiers.none.#{feminine ? 'short_f' : 'short'}")} #{items_long(name, node, :one)}#{where}#{window}")
        else
          t("sentence.all_items", owner: owner(found), items: "#{items_long(name, node, :other)}#{window}", where: where.strip.presence || items_long(name, node, :other))
        end
      end

      def where_long(name, spec, where)
        field = where["field"].to_s
        t("sentence.with", field: t("fields.#{name}.#{field}"), op: long_comparison(where, spec[:fields].fetch(field.to_sym), field, name))
      end

      def items_long(name, node, number) = items_short(name, node, number)

      def long_count(node)
        op = node["op"]
        return t("ops.count_long.between", low: node["value"].first, high: node["value"].last) if op == "between"

        t("ops.count_long.#{op}", value: node["value"])
      end

      def short_comparison(node, spec, field, collection = nil)
        op = node["op"]
        case op
        when "between"
          low, high = node["value"]
          t("ops.between_short", low: value_short(low, spec, field, collection), high: value_short(high, spec, field, collection))
        when "in"
          t("ops.in_short", values: Array(node["value"]).map { |value| value_short(value, spec, field, collection) }.join(", "))
        else
          "#{t("ops.symbols.#{op}")} #{value_short(node['value'], spec, field, collection)}"
        end
      end

      def long_comparison(node, spec, field, collection = nil)
        op = node["op"]
        case op
        when "between"
          low, high = node["value"]
          t("ops.long.between", low: value_long(low, spec, field, collection), high: value_long(high, spec, field, collection))
        when "in"
          t("ops.long.in", values: Array(node["value"]).map { |value| value_long(value, spec, field, collection) }.join(", "))
        else
          t("ops.long.#{op}", value: value_long(node["value"], spec, field, collection))
        end
      end

      def value_short(value, spec, field, collection)
        case spec[:type]
        when :money then Text.money(value, full: false)
        when :percent then "#{value}%"
        when :option then option_label(value, field, collection, long: false)
        when :reference then result_name(value)
        when :user then "\"#{user_name(value)}\""
        else value.to_s
        end
      end

      def value_long(value, spec, field, collection)
        case spec[:type]
        when :money then Text.money(value, full: true)
        when :percent then "#{value}%"
        when :days then I18n.t("segment_language.values.days", count: value)
        when :option then option_label(value, field, collection, long: true)
        when :reference then "\"#{result_name(value)}\""
        when :user then "\"#{user_name(value)}\""
        else value.to_s
        end
      end

      OPTION_SETS = { [ nil, "person_type" ] => "person_type", [ "customers", "person_type" ] => "person_type", [ "bills", "kind" ] => "kind",
                      [ "contacts", "kind" ] => "contact_kind", [ "contacts", "status" ] => "status", [ "contacts", "origin" ] => "origin",
                      [ "contact_attempts", "result_kind" ] => "result_kind", [ "contact_attempts", "channel" ] => "channel",
                      [ "promises", "state" ] => "promise_state", [ "agreements", "state" ] => "agreement_state", [ "agreements", "mode" ] => "mode",
                      [ "payments", "method" ] => "method" }.freeze

      def option_label(value, field, collection, long:)
        set = OPTION_SETS[[ collection, field.to_s ]] || OPTION_SETS[[ nil, field.to_s ]]
        set = "person_type_long" if set == "person_type" && long
        set ? t("options.#{set}.#{value}") : value.to_s
      end

      def result_name(id)
        @result_names ||= ContactResult.where(id: result_ids).pluck(:id, :name).to_h
        @result_names[id] || t("unknown_result")
      end

      def user_name(id) = (@user_names ||= {})[id] ||= (User.find_by(id: id)&.name || t("unknown_user"))

      def result_ids
        ids = []
        @expression.each_condition do |node, _|
          ids << node.dig("where", "value") if node["path"].to_s.end_with?("contact_attempts") && node.dig("where", "field") == "result"
        end
        ids.flatten.compact
      end

    # Dinheiro em centavos: "R$ 5.000" no texto curto (centavos só quando há), "R$ 5.000,00" por extenso.
    def self.money(cents, full: true)
      reais, rest = cents.to_i.divmod(100)
      integer = reais.to_s.reverse.scan(/\d{1,3}/).join(".").reverse
      full || rest.positive? ? "R$ #{integer},#{format('%02d', rest)}" : "R$ #{integer}"
    end
  end
end
