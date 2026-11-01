module Segments
  # Glossário da linguagem dos segmentos (13, R289), gerado do catálogo e do idioma, para nunca divergir deles: cada termo com o texto curto, a
  # definição e um exemplo com a leitura por extenso. Atributo novo no catálogo aparece aqui sem edição à mão.
  module Glossary
    Entry = Data.define(:anchor, :term, :definition, :example, :reading, :details)
    Section = Data.define(:title, :entries)

    module_function

    def entries
      [
        Section.new("O que o segmento seleciona", Catalog::SUBJECTS.map { |subject| Entry.new("sujeito-#{subject}", t("subjects.#{subject}.short"), t("subjects.#{subject}.definition"), nil, nil, nil) }),
        Section.new("Do contrato", attributes("contracts")),
        Section.new("Do cliente", attributes("customers")),
        Section.new("Clientes do contrato (pais)", parents),
        Section.new("Coleções", collections),
        Section.new("Como comparar e contar", grammar)
      ]
    end

    def t(key, **options) = I18n.t("segment_language.#{key}", **options)

    def sample(subject, node)
      text = Text.new(Expression.new("grammar" => Expression::GRAMMAR, "subject" => subject, "all" => [ node ]), result_names: {})
      [ text.short(node), text.long(node) ]
    end

    def attributes(subject)
      Catalog.attributes_of(subject).map do |name, spec|
        node = example_node(name.to_s, spec)
        short, long = sample(subject, node)
        Entry.new("#{subject}-#{name}", t("attributes.#{subject}.#{name}.short"), t("attributes.#{subject}.#{name}.definition"), short, long, nil)
      end
    end

    def parents
      Catalog::PARENTS.map do |parent|
        short, long = sample("contracts", { "path" => "#{parent}.person_type", "op" => "eq", "value" => "company" })
        Entry.new("pai-#{parent}", t("parents.#{parent}.short"), t("parents.#{parent}.definition"), short, long, nil)
      end
    end

    def collections
      Catalog::COLLECTIONS.map do |name, spec|
        subject = Catalog::SUBJECT_COLLECTIONS["contracts"].include?(name.to_s) || name == :other_contracts ? "contracts" : "customers"
        path = name == :other_contracts ? "holder.other_contracts" : name.to_s
        node = { "path" => path, "aggregate" => "count", "op" => "gte", "value" => 2 }
        node["within_days"] = 30 if spec[:dated]
        short, long = sample(subject, node)
        details = []
        details << "Campos: #{spec[:fields].keys.map { |field| t("fields.#{name}.#{field}") }.join(', ')}."
        details << "Atalho entre aspas: compara o campo #{t("fields.#{name}.#{spec[:main]}")}." if spec[:main]
        details << "Qualificadores: #{spec[:qualifiers].map { |qualifier| t("qualifiers.#{name}.#{qualifier}.other") }.join(', ')}." if spec[:qualifiers].any?
        details << "Aceita a janela \"em N dias\"." if spec[:dated]
        Entry.new("colecao-#{name}", t("collections.#{name}.other"), t("collections.#{name}.definition"), short, long, details.join(" "))
      end
    end

    def grammar
      [
        Entry.new("comparacoes", "= ≠ > >= < <=", "Igual, diferente, maior, pelo menos, menor e no máximo.", "atraso >= 30", sample("contracts", { "path" => "overdue_days", "op" => "gte", "value" => 30 }).last, nil),
        Entry.new("entre", "entre A e B", "Dentro da faixa, com as duas pontas.", "atraso entre 30 e 90", sample("contracts", { "path" => "overdue_days", "op" => "between", "value" => [ 30, 90 ] }).last, nil),
        Entry.new("em", "em A, B", "Igual a um dos valores da lista.", "tipo em PF, misto", sample("contracts", { "path" => "person_type", "op" => "in", "value" => %w[person mixed] }).last, nil),
        Entry.new("quantidade", "coleção com número", "A coleção comparada a um número é a quantidade de itens.", *sample("contracts", { "path" => "bills", "qualifier" => "overdue", "aggregate" => "count", "op" => "gte", "value" => 3 }), nil),
        Entry.new("soma", "soma, maior, menor", "Soma, maior ou menor valor de um campo dos itens da coleção.", *sample("contracts", { "path" => "bills", "aggregate" => "sum", "field" => "balance", "op" => "gt", "value" => 500_000 }), nil),
        Entry.new("algum", "algum, todos, nenhum, sem", "Se algum item, todos os itens ou nenhum item atende; \"sem\" é nenhum, sem condição sobre o item. \"Todos\" exige pelo menos um item.",
                  *sample("contracts", { "path" => "promises", "quantifier" => "some", "where" => { "field" => "state", "op" => "eq", "value" => "broken" } }), nil),
        Entry.new("janela", "em N dias", "Só os itens dos últimos N dias, contados até hoje.", *sample("contracts", { "path" => "contact_attempts", "quantifier" => "none", "within_days" => 30 }), nil),
        Entry.new("qualquer", "qualquer:", "Abre um grupo: basta uma das condições de dentro. Fora do grupo, todas as linhas valem juntas.", nil, nil, nil),
        Entry.new("nao", "não", "Nega a linha.", "não quebrou acordo", sample("contracts", { "path" => "broke_agreement", "op" => "is", "negate" => true }).last, nil)
      ]
    end

    def example_node(name, spec)
      case spec[:type]
      when :boolean then { "path" => name, "op" => "is" }
      when :option then { "path" => name, "op" => "eq", "value" => spec[:options].first }
      when :text then { "path" => name, "op" => "eq", "value" => "Mensalidade" }
      when :money then { "path" => name, "op" => "gt", "value" => 500_000 }
      when :percent then { "path" => name, "op" => "gte", "value" => 80 }
      else { "path" => name, "op" => "gt", "value" => 90 }
      end
    end
  end
end
