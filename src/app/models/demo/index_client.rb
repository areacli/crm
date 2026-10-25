module Demo
  # Cliente de índices da demonstração: no lugar do Banco Central (nenhuma chamada de saída). Devolve variações mensais fictícias, estáveis e
  # plausíveis para as cinco séries, no mesmo formato da API SGS, de janeiro de 2020 ao mês pedido.
  class IndexClient
    RANGES = { 433 => [ 0.05, 0.85 ], 188 => [ 0.03, 0.9 ], 189 => [ -0.4, 1.1 ], 4390 => [ 0.7, 1.2 ], 29543 => [ 0.55, 1.2 ] }.freeze

    def series(code, from:, to:)
      low, high = RANGES.fetch(Integer(code))
      month = [ from.beginning_of_month, Date.new(2020, 1, 1) ].max
      rows = []
      while month <= to
        step = (Zlib.crc32("#{code}:#{month}") % 1000) / 1000.0
        rows << { "data" => month.strftime("%d/%m/%Y"), "valor" => format("%.2f", low + (high - low) * step) }
        month = month.next_month
      end
      rows
    end
  end
end
