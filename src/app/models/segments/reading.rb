module Segments
  # A coluna "Como fica" do editor (13, R278, R302): para cada linha escrita, a leitura por extenso ou o erro; e o segmento inteiro por extenso.
  class Reading
    Line = Data.define(:number, :text, :errors, :reading)

    attr_reader :subject

    def initialize(source, parsed, subject)
      @source = source.to_s
      @parsed = parsed
      @subject = parsed.subject || subject || "contracts"
      @errors = parsed.errors.group_by(&:first).transform_values { |list| list.map(&:last) }
    end

    def lines
      @source.split(/\r?\n/).each_with_index.filter_map do |line, index|
        next if line.strip.empty?

        number = index + 1
        errors = @errors.fetch(number, [])
        Line.new(number, line.strip, errors, (errors.empty? ? reading_of(number) : nil))
      end
    end

    # Erro sem linha escrita para mostrar junto, como a caixa vazia.
    def loose_errors
      written = lines.map(&:number)
      @errors.reject { |number, _| written.include?(number) }.values.flatten
    end

    def ok? = @parsed.ok?

    def error_count = @errors.size

    def expression = (Expression.new(@parsed.tree) if ok?)

    # O segmento inteiro por extenso, ou "Escreva pelo menos uma condição."
    def long_text = (Text.new(expression).long_text.presence || "Escreva pelo menos uma condição." if ok?)

    private
      def reading_of(number)
        node = @parsed.nodes[number]
        if number == first_line then "Seleciona #{I18n.t("segment_language.subjects.#{subject}.long")}."
        elsif node == :group then "Pelo menos uma das linhas de baixo."
        elsif node then "#{Text.new(Expression.new("grammar" => 1, "subject" => subject, "all" => [ node ])).long(node).upcase_first}."
        end
      end

      def first_line = @source.split(/\r?\n/).index { |line| line.strip.present? }.to_i + 1
  end
end
