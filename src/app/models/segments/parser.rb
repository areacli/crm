module Segments
  # O analisador da linguagem dos segmentos (13, revisão 4, R301 a R304): o texto que o gestor escreve vira a árvore (decisão 0023). É o inverso
  # do texto curto (`Text`): aceita exatamente o que a tela escreve, sem diferença de maiúsculas, acentos e espaços. Cada linha com problema dá um
  # erro em português com o número da linha e o que se esperava; a árvore só sai quando não há erro.
  class Parser
    Line = Data.define(:number, :indent, :text)
    # `nodes`: o nó de cada linha que se leu bem ({ número da linha => nó }); `:group` na linha do "qualquer:".
    # `subject`: o da primeira linha, quando ela é válida (mesmo com erro nas outras).
    Result = Data.define(:tree, :errors, :nodes, :subject) do
      def ok? = errors.empty?
    end

    class Error < StandardError; end

    ACCENTED = "áàâãäéèêëíìîïóòôõöúùûüç".freeze
    PLAIN = "aaaaaeeeeiiiiooooouuuuc".freeze
    OPS = [ [ ">=", "gte" ], [ "<=", "lte" ], [ "!=", "ne" ], [ "<>", "ne" ], [ "≠", "ne" ], [ "=", "eq" ], [ ">", "gt" ], [ "<", "lt" ] ].freeze
    WINDOW = /\s+em\s+(\d+)\s+dias?\z/

    # `tenant`: para achar o resultado de acionamento pelo nome. `subject`: o do segmento gravado, que não muda (R304).
    def initialize(tenant, subject: nil)
      @tenant = tenant
      @fixed_subject = subject
    end

    def self.fold(text) = text.to_s.unicode_normalize(:nfc).downcase.tr(ACCENTED, PLAIN)

    def parse(source)
      @errors = []
      lines = source.to_s.gsub("\t", "  ").split(/\r?\n/).each_with_index.filter_map do |raw, index|
        next if raw.strip.empty?

        Line.new(index + 1, raw[/\A */].size, raw.strip.unicode_normalize(:nfc).squish)
      end
      return Result.new(nil, [ [ 1, t("empty_text") ] ], {}, nil) if lines.empty?

      subject = subject_of(lines.first)
      return Result.new(nil, @errors, {}, nil) unless subject

      @subject = subject
      all = []
      numbers = {}
      nodes = {}
      group = nil
      lines.drop(1).each do |line|
        if self.class.fold(line.text).delete_suffix(":") == "qualquer"
          group = { "line" => line, "nodes" => [] }
          all << group
          nodes[line.number] = :group
          next
        end
        group = nil if group && line.indent <= group["line"].indent
        node = condition(line)
        next unless node

        nodes[line.number] = node
        if group
          numbers["#{all.index(group)}.#{group['nodes'].size}"] = line.number
          group["nodes"] << node
        else
          numbers[all.size.to_s] = line.number
          all << node
        end
      end
      all.each_with_index do |item, index|
        next unless item.is_a?(Hash) && item.key?("line")

        @errors << [ item["line"].number, t("group_empty") ] if item["nodes"].empty?
        all[index] = { "any" => item["nodes"] }
      end
      tree = { "grammar" => Expression::GRAMMAR, "subject" => subject, "all" => all }
      validate(tree, numbers) if @errors.empty?
      Result.new(@errors.empty? ? tree : nil, @errors.sort_by(&:first), nodes, subject)
    end

    private
      def t(key, **options) = I18n.t("segment_language.parse_errors.#{key}", **options)
      def lt(key) = I18n.t("segment_language.#{key}")
      def fold(text) = self.class.fold(text)

      def subject_of(line)
        subject = Catalog::SUBJECTS.find { |key| fold(lt("subjects.#{key}.short")) == fold(line.text) }
        return (@errors << [ line.number, t("subject", found: line.text) ]) && nil unless subject

        if @fixed_subject && subject != @fixed_subject
          @errors << [ line.number, t("subject_fixed", subject: lt("subjects.#{@fixed_subject}.short")) ]
          return nil
        end
        subject
      end

      # A árvore montada ainda passa pela validação do catálogo (faixas, valores, limites), e o erro volta para a linha dele.
      def validate(tree, numbers)
        expression = Expression.new(tree)
        return if expression.valid?

        expression.errors.each do |address, messages|
          messages.each { |message| @errors << [ numbers[address] || 1, message ] }
        end
      end

      def condition(line)
        Scanner.new(self, line.text, @subject, @tenant).node
      rescue Error => error
        @errors << [ line.number, t("line", number: line.number, message: error.message) ]
        nil
      end

      # Lê uma linha de condição da esquerda para a direita: "não", pai, quantificador ou agregação, atributo ou coleção, qualificador, comparação
      # e valor, janela de dias. Cada palavra-chave é comparada sem acento e sem maiúsculas; o valor sai do texto original.
      class Scanner
        def initialize(parser, text, subject, tenant)
          @parser = parser
          @text = text
          @folded = Parser.fold(text)
          @subject = subject
          @tenant = tenant
          @pos = 0
        end

        def node
          node = {}
          window = @folded.match(Parser::WINDOW)
          if window
            node["within_days"] = window[1].to_i
            @text = @text[0, window.begin(0)]
            @folded = @folded[0, window.begin(0)]
          end
          node["negate"] = true if word("nao")
          parent = Catalog::PARENTS.find { |key| @subject == "contracts" && word(fold_t("parents.#{key}.short")) }
          return boolean(node, parent) if boolean?(parent)

          quantifier = quantifier_word
          aggregate = quantifier ? nil : %w[sum max min].find { |key| word(fold_t("aggregates.#{key}.short")) }
          unless quantifier || aggregate
            attribute = attribute_name(parent)
            return attribute_node(node, parent, attribute) if attribute
          end
          if aggregate
            field = aggregate_field
            raise Error, msg("aggregate_field") unless field
          end
          name = collection_name(parent, singular: quantifier && quantifier != "all")
          raise Error, msg(parent || quantifier || aggregate ? "collection" : "start") unless name
          spec = Catalog.collection(name)
          raise Error, msg("window") if node["within_days"] && !spec[:dated]
          path = parent ? "#{parent}.#{name}" : name
          node["path"] = path
          qualifier = qualifier_name(name, spec, singular: quantifier && quantifier != "all")
          node["qualifier"] = qualifier if qualifier
          if quantifier
            node["quantifier"] = quantifier == "without" ? "none" : quantifier
            where(node, name, spec) unless quantifier == "without"
          elsif aggregate
            node["aggregate"] = aggregate
            node["field"] = field_key(name, spec, field)
            comparison(node, spec[:fields].fetch(node["field"].to_sym), name, node["field"])
          else
            node["aggregate"] = "count"
            comparison(node, { type: :count }, name, nil)
          end
          finish!
          node.compact
        end

        private
          def fold_t(key) = Parser.fold(I18n.t("segment_language.#{key}"))
          def msg(key, **options) = I18n.t("segment_language.parse_errors.#{key}", **options)
          def rest = @folded[@pos..].to_s.strip
          def rest_original = @text[@pos..].to_s.strip

          # Consome a palavra (ou expressão) se o texto continua com ela, seguida de espaço ou do fim.
          def word(phrase)
            phrase = Parser.fold(phrase)
            skip_spaces
            return false unless @folded[@pos..].to_s.start_with?(phrase)

            after = @folded[@pos + phrase.size]
            return false unless after.nil? || after == " " || !phrase[-1].match?(/[[:alnum:]]/)

            @pos += phrase.size
            true
          end

          def skip_spaces = (@pos += 1 while @folded[@pos] == " ")

          # A mais longa entre as opções que casa no ponto atual.
          def longest(options)
            options.sort_by { |label, _| -label.size }.find { |label, _| word(label) }&.last
          end

          def finish!
            skip_spaces
            raise Error, msg("leftover", text: rest_original) unless @pos >= @folded.size
          end

          def boolean?(parent)
            return false if parent || @subject != "contracts"

            %w[broke_agreement in_arrears in_collection].any? { |key| rest == fold_t("attributes.contracts.#{key}.short") }
          end

          def boolean(node, _parent)
            key = %w[broke_agreement in_arrears in_collection].find { |name| rest == fold_t("attributes.contracts.#{name}.short") }
            { "path" => key, "op" => "is", "negate" => node["negate"] }.compact
          end

          def quantifier_word
            return "without" if word(fold_t("quantifiers.without"))

            { "some" => %w[short short_f], "none" => %w[short short_f], "all" => %w[short short_f] }.each do |key, forms|
              forms.each { |form| return key if word(fold_t("quantifiers.#{key}.#{form}")) }
            end
            nil
          end

          def attribute_name(parent)
            set = parent ? Catalog::CUSTOMER_ATTRIBUTES : Catalog.attributes_of(@subject)
            scope = parent ? "customers" : @subject
            options = set.keys.map { |key| [ fold_t("attributes.#{scope}.#{key}.short"), key.to_s ] }
            longest(options.reject { |_, key| set[key.to_sym][:type] == :boolean })
          end

          def attribute_node(node, parent, name)
            spec = parent ? Catalog::CUSTOMER_ATTRIBUTES.fetch(name.to_sym) : Catalog.attributes_of(@subject).fetch(name.to_sym)
            raise Error, msg("window") if node["within_days"]

            node["path"] = parent ? "#{parent}.#{name}" : name
            comparison(node, spec, nil, name)
            finish!
            node.compact
          end

          def collection_name(parent, singular:)
            names = parent ? Catalog::PARENT_COLLECTIONS : Catalog::SUBJECT_COLLECTIONS.fetch(@subject)
            longest(names.map { |key| [ fold_t("collections.#{key}.#{singular ? 'one' : 'other'}"), key ] })
          end

          def qualifier_name(name, spec, singular:)
            return nil if spec[:qualifiers].empty?

            longest(spec[:qualifiers].map { |key| [ fold_t("qualifiers.#{name}.#{key}.#{singular ? 'one' : 'other'}"), key ] })
          end

          # O campo da agregação vem antes da coleção ("soma saldo títulos"): guarda o rótulo e confere depois de saber a coleção.
          def aggregate_field
            labels = Catalog::COLLECTIONS.flat_map { |name, spec| spec[:sums].map { |field| fold_t("fields.#{name}.#{field}") } }.uniq
            longest(labels.map { |label| [ label, label ] })
          end

          def field_key(name, spec, label)
            key = spec[:sums].find { |field| fold_t("fields.#{name}.#{field}") == label }
            raise Error, msg("aggregate_field") unless key

            key.to_s
          end

          # Depois de "algum título": nada, o atalho entre aspas (campo principal, SG14) ou "com campo comparação valor".
          def where(node, name, spec)
            skip_spaces
            return if @pos >= @folded.size

            if @text[@pos] == "\""
              values = rest_original.scan(/"([^"]*)"/).flatten
              raise Error, msg("quotes") if values.empty?

              field = spec[:main].to_s
              field_spec = spec[:fields].fetch(spec[:main])
              parsed = values.map { |value| value(value, field_spec, name, field) }
              node["where"] = { "field" => field, "op" => parsed.size == 1 ? "eq" : "in", "value" => parsed.size == 1 ? parsed.first : parsed }
              @pos = @folded.size
              return
            end
            raise Error, msg("with") unless word("com")

            field = longest(spec[:fields].keys.map { |key| [ fold_t("fields.#{name}.#{key}"), key.to_s ] })
            raise Error, msg("field", fields: spec[:fields].keys.map { |key| I18n.t("segment_language.fields.#{name}.#{key}") }.join(", ")) unless field

            where = { "field" => field }
            comparison(where, spec[:fields].fetch(field.to_sym), name, field)
            node["where"] = where
          end

          def comparison(node, spec, collection, field)
            skip_spaces
            op = Parser::OPS.find { |symbol, _| @folded[@pos..].to_s.start_with?(symbol) }
            if op
              @pos += op.first.size
              node["op"] = op.last
              node["value"] = value(rest_original, spec, collection, field)
            elsif word("entre")
              low, high = rest_original.split(/\s+e\s+/i, 2)
              raise Error, msg("between") unless high

              node["op"] = "between"
              node["value"] = [ value(low, spec, collection, field), value(high, spec, collection, field) ]
            elsif word("em")
              items = rest_original.include?("\"") ? rest_original.scan(/"([^"]*)"/).flatten : rest_original.split(",")
              node["op"] = "in"
              node["value"] = items.map(&:strip).compact_blank.map { |item| value(item, spec, collection, field) }
              raise Error, msg("list") if node["value"].empty?
            else
              raise Error, msg("comparison")
            end
            @pos = @folded.size
            node
          end

          def value(raw, spec, collection, field)
            text = raw.to_s.strip.delete_prefix("\"").delete_suffix("\"").strip
            raise Error, msg("value") if text.empty?

            case spec[:type]
            when :days, :count
              number = text.sub(/\s*(dias?|itens?)\z/i, "")
              raise Error, msg("number", text: text) unless number.match?(/\A\d+\z/)

              number.to_i
            when :percent
              number = text.delete("%").strip
              raise Error, msg("number", text: text) unless number.match?(/\A\d+\z/)

              number.to_i
            when :money
              money = text.delete_prefix("R$").strip
              cents = ::Money.parse_cents(money).first || (money.match?(/\A0+(,0{1,2})?\z/) ? 0 : nil)
              raise Error, msg("money", text: text) unless cents

              cents
            when :option then option(text, spec, collection, field)
            when :reference
              # O valor é guardado pelo id e escrito pelo nome: resultado de acionamento ou sistema do credor (17, R425), conforme o campo.
              model, error = spec[:of] == :system ? [ SourceSystem, "system" ] : [ ContactResult, "result" ]
              found = model.where(tenant_id: @tenant.id).find { |candidate| Parser.fold(candidate.name) == Parser.fold(text) }
              raise Error, msg(error, text: text) unless found

              found.id
            when :user
              user = User.joins(:memberships).where(memberships: { tenant_id: @tenant.id }).distinct.find do |candidate|
                [ candidate.name, candidate.email_address ].any? { |label| Parser.fold(label) == Parser.fold(text) }
              end
              raise Error, msg("user", text: text) unless user

              user.id
            else text
            end
          end

          def option(text, spec, collection, field)
            set = Text::OPTION_SETS[[ collection, field.to_s ]] || Text::OPTION_SETS[[ nil, field.to_s ]]
            found = spec[:options].find do |key|
              labels = [ key ]
              labels << I18n.t("segment_language.options.#{set}.#{key}") if set
              labels << I18n.t("segment_language.options.person_type_long.#{key}") if set == "person_type"
              labels.any? { |label| Parser.fold(label) == Parser.fold(text) }
            end
            unless found
              names = spec[:options].map { |key| set ? I18n.t("segment_language.options.#{set}.#{key}") : key }
              raise Error, msg("option", text: text, options: names.join(", "))
            end
            found
          end
      end
  end
end
