module Segments
  # A árvore de um segmento (decisão 0023, seção 1), validada contra o catálogo. Forma (chaves em texto, como volta do `jsonb`):
  #
  #   { "grammar" => 1, "subject" => "contracts", "all" => [condição, ...] }
  #
  # Condição sobre atributo: { "path", "op", "value", "negate" }; sobre coleção: { "path", "qualifier", e "aggregate" + "field" + "op" + "value"
  # (quantidade, soma, maior, menor) ou "quantifier" + "where" (algum, todos, nenhum), "within_days", "negate" }; grupo "qualquer":
  # { "any" => [condição, ...] }, um nível só (R254). Dinheiro em centavos, percentual inteiro, dias inteiros; o resultado de acionamento pelo id.
  class Expression
    GRAMMAR = 1

    attr_reader :tree, :errors

    def self.empty(subject) = new({ "grammar" => GRAMMAR, "subject" => subject, "all" => [] })

    def initialize(tree)
      @tree = (tree || {}).deep_stringify_keys
      @errors = {}
    end

    def subject = tree["subject"]
    def conditions = Array(tree["all"])

    # As condições soltas (sem grupo) e as de dentro dos grupos, com o endereço de cada uma ("2" ou "4.1"), na ordem do texto.
    def each_condition
      return enum_for(:each_condition) unless block_given?

      conditions.each_with_index do |node, index|
        if node.key?("any")
          Array(node["any"]).each_with_index { |inner, inner_index| yield inner, "#{index}.#{inner_index}" }
        else
          yield node, index.to_s
        end
      end
    end

    def count = each_condition.count

    def valid?
      @errors = {}
      add(:base, :subject) unless Catalog::SUBJECTS.include?(subject)
      add(:base, :grammar) unless tree["grammar"] == GRAMMAR
      add(:base, :empty) if count.zero?
      add(:base, :too_many, count: Catalog::MAX_CONDITIONS) if count > Catalog::MAX_CONDITIONS
      conditions.each_with_index do |node, index|
        if node.key?("any")
          inner = Array(node["any"])
          add(index.to_s, :group_empty) if inner.empty?
          inner.each_with_index { |child, child_index| child.key?("any") ? add("#{index}.#{child_index}", :nested_group) : check(child, "#{index}.#{child_index}") }
        else
          check(node, index.to_s)
        end
      end
      @errors.empty?
    end

    def ==(other) = other.is_a?(Expression) && tree == other.tree

    private
      def add(where, key, **options) = (@errors[where.to_s] ||= []) << I18n.t("segment_language.errors.#{key}", **options)

      def check(node, where)
        return add(where, :incomplete) unless node.is_a?(Hash)

        found = Catalog.resolve(subject, node["path"])
        return add(where, :path) unless found

        found[:kind] == :attribute ? check_attribute(node, found[:spec], where) : check_collection(node, found, where)
      end

      def check_attribute(node, spec, where) = check_comparison(node, spec, where)

      def check_collection(node, found, where)
        spec = found[:spec]
        add(where, :qualifier) if node["qualifier"].present? && !spec[:qualifiers].include?(node["qualifier"])
        if node["within_days"].present?
          days = node["within_days"]
          add(where, :window) unless spec[:dated] && days.is_a?(Integer) && days.between?(1, Catalog::MAX_WINDOW_DAYS)
        end
        if node["aggregate"].present?
          check_aggregate(node, spec, where)
        elsif node["quantifier"].present?
          add(where, :quantifier) unless Catalog::QUANTIFIERS.include?(node["quantifier"])
          check_where(node["where"], spec, where) if node["where"].present?
        else
          add(where, :incomplete)
        end
      end

      def check_aggregate(node, spec, where)
        aggregate = node["aggregate"]
        return add(where, :aggregate) unless Catalog::AGGREGATES.include?(aggregate)
        return check_comparison(node, { type: :count }, where) if aggregate == "count"

        field = node["field"].to_s
        return add(where, :field) unless spec[:sums].map(&:to_s).include?(field)

        check_comparison(node, spec[:fields].fetch(field.to_sym), where)
      end

      def check_where(condition, spec, where)
        return add(where, :incomplete) unless condition.is_a?(Hash)

        field_spec = spec[:fields][condition["field"].to_s.to_sym]
        return add(where, :field) unless field_spec

        check_comparison(condition, field_spec, where)
      end

      # Comparação aceita para o tipo, e valor no formato e na faixa (casos de exceção da 13: linha incompleta, faixa invertida, % acima de 100).
      def check_comparison(node, spec, where)
        op = node["op"]
        return add(where, :op) unless Catalog::OPS.fetch(spec[:type]).include?(op)
        return if spec[:type] == :boolean

        value = node["value"]
        case op
        when "between"
          return add(where, :incomplete) unless value.is_a?(Array) && value.size == 2 && value.all? { |item| valid_value?(item, spec) }

          add(where, :range_inverted) if value.first > value.last
        when "in"
          add(where, :incomplete) unless value.is_a?(Array) && value.any? && value.all? { |item| valid_value?(item, spec) }
        else
          add(where, :incomplete) unless valid_value?(value, spec)
        end
        add(where, :percent) if spec[:type] == :percent && Array(value).any? { |item| item.is_a?(Integer) && item > 100 }
      end

      def valid_value?(value, spec)
        case spec[:type]
        when :days, :count, :money, :percent then value.is_a?(Integer) && !value.negative?
        when :option then spec[:options].include?(value)
        when :reference, :user then value.is_a?(Integer) && value.positive?
        when :text then value.is_a?(String) && value.strip.present? && value.size <= 100
        else false
        end
      end
  end
end
