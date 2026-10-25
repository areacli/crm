module Charges
  # Tabelas por dia, de 01/01/2000 até hoje (DS2), montadas uma vez por cálculo a partir dos índices gravados e das políticas do credor: o
  # fator acumulado de correção de cada série (IPCA, INPC, IGP-M) e o acumulado de juros simples da Selic e da taxa legal, no fim de cada dia.
  # A correção ou os juros entre dois dias são a divisão ou a diferença de dois valores da tabela (medido: cerca de 250 mil títulos por segundo).
  #
  # Posição de um dia no tempo: meses desde janeiro de 2000 mais dia ÷ dias do mês (fim do dia). De 15/07 a 31/07 são 16/31 de julho e de 01/10
  # a 21/10 são 21/31 de outubro (exemplo de Maria, R165 e R166).
  class Tables
    START = Date.new(2000, 1, 1)
    CORRECTION = %w[ipca inpc igpm].freeze
    INTEREST = %w[selic legal].freeze

    attr_reader :today, :policies, :pos, :corr, :interest, :notes

    # Índice do fim do dia `date` (0 = fim de 31/12/1999). Dias anteriores a 2000 ficam no começo (caso de exceção da 09).
    START_JD = START.jd

    # Aritmética inteira sobre o dia juliano: subtrair duas datas cria um Rational, e essa conta roda milhões de vezes no recálculo.
    def self.k(date)
      k = date.jd - START_JD + 1
      k.negative? ? 0 : k
    end

    # Data do dia cujo fim é o índice k.
    def self.day(k) = START + (k - 1)

    # `rates`: { série => { mês (Date) => percentual (Float) } }, só meses fechados e já com a correção do credor.
    def initialize(rates, today, policies)
      @today = today
      @policies = policies
      size = self.class.k(today) + 1
      @pos = Array.new(size, 0.0)
      @corr = CORRECTION.index_with { Array.new(size, 1.0) }
      @interest = INTEREST.index_with { Array.new(size, 0.0) }
      @notes = (CORRECTION + INTEREST).index_with { {} } # mês => "estimado pelo de mm/aaaa" ou "sem índice publicado" (memória de cálculo)
      months = []
      month = START
      while month <= today
        months << month
        month = month.next_month
      end
      (CORRECTION + INTEREST).each { |series| build(series, rates.fetch(series, {}), months, size) }
    end

    private
      def build(series, values, months, size)
        correction = CORRECTION.include?(series)
        last = nil
        total = correction ? 1.0 : 0.0
        months.each_with_index do |month, i|
          value = values[month]
          if value
            last = [ month, value ]
            rate = value
          elsif policies.missing_index == "last_prorated" && last
            rate = last[1]
            @notes[series][month] = "estimado pelo de #{last[0].strftime('%m/%Y')}"
          else
            rate = 0.0
            @notes[series][month] = "sem índice publicado"
          end
          if correction && policies.negative_index == "ignore" && rate.negative?
            @notes[series][month] = "negativo, contado como 0%"
            rate = 0.0
          end
          days = Time.days_in_month(month.month, month.year)
          first = self.class.k(month)
          (1..days).each do |day|
            k = first + day - 1
            break if k >= size

            @pos[k] = i + day.to_f / days if series == CORRECTION.first
            if correction
              @corr[series][k] = total * (1 + rate / 100)**(day.to_f / days)
            else
              @interest[series][k] = total + rate / 100 * day / days
            end
          end
          total = correction ? total * (1 + rate / 100) : total + rate / 100
        end
      end
  end
end
