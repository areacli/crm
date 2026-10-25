module Portfolio
  # Faixas de atraso do credor (R18): começam em 1 dia, não têm buraco nem sobreposição e a última é aberta.
  # Cada faixa é { from: início, to: fim ou nil }.
  class AgingBrackets
    attr_reader :brackets

    def initialize(brackets) = @brackets = brackets.freeze

    # @raise [InvalidBrackets]
    def self.from(input)
      raise InvalidBrackets, "informe ao menos uma faixa" if input.blank?

      brackets = input.map do |bracket|
        bracket = bracket.to_h.with_indifferent_access
        { from: Integer(bracket[:from], exception: false) || raise(InvalidBrackets, "início da faixa inválido"),
          to: bracket[:to].nil? || bracket[:to].to_s.strip.empty? ? nil : (Integer(bracket[:to], exception: false) || raise(InvalidBrackets, "fim da faixa inválido")) }
      end.sort_by { |bracket| bracket[:from] }
      raise InvalidBrackets, "as faixas começam em 1 dia de atraso" unless brackets.first[:from] == 1

      brackets.each_with_index do |bracket, index|
        last = index == brackets.size - 1
        raise InvalidBrackets, "a última faixa deve ser aberta (sem fim)" if last && bracket[:to]
        raise InvalidBrackets, "só a última faixa pode ser aberta" if !last && bracket[:to].nil?
        raise InvalidBrackets, "faixa #{bracket[:from]} a #{bracket[:to]} com fim antes do início" if bracket[:to] && bracket[:to] < bracket[:from]
        next if last

        following = brackets[index + 1]
        raise InvalidBrackets, "faixas sobrepostas: #{following[:from]} a #{bracket[:to]}" if following[:from] <= bracket[:to]
        raise InvalidBrackets, "buraco entre as faixas: #{bracket[:to] + 1} a #{following[:from] - 1}" if following[:from] > bracket[:to] + 1
      end
      new(brackets)
    end

    # As faixas guardadas (jsonb) voltam como hashes de chave texto.
    def self.from_stored(stored) = from(stored)

    # Índice da faixa (a partir de 0) em que os dias de atraso caem; nil para quem não está em atraso.
    def index_for(days_overdue)
      return if days_overdue < 1

      brackets.index { |bracket| days_overdue >= bracket[:from] && (bracket[:to].nil? || days_overdue <= bracket[:to]) }
    end

    def label(index)
      bracket = brackets.fetch(index)
      bracket[:to].nil? ? "mais de #{bracket[:from] - 1}" : "#{bracket[:from]}–#{bracket[:to]}"
    end

    def labels = brackets.each_index.map { |index| label(index) }

    # Expressão SQL que dá o índice da faixa para uma coluna de dias de atraso. Os limites são inteiros validados, nunca texto do usuário.
    def sql_index(days_column)
      whens = brackets.each_with_index.map do |bracket, index|
        bracket[:to].nil? ? "when #{days_column} >= #{bracket[:from]} then #{index}" : "when #{days_column} between #{bracket[:from]} and #{bracket[:to]} then #{index}"
      end
      "case #{whens.join(' ')} end"
    end
  end
end
