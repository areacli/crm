require "csv"

module Portfolio
  # Leitor do CSV da carteira: separador `;`, UTF-8 ou Windows-1252, cabeçalho obrigatório com as colunas em qualquer ordem, sem
  # diferenciar maiúsculas nem acentos (formato da planilha, especificação 01). Lê registro a registro, sem carregar o arquivo inteiro.
  class CsvFile
    REQUIRED = %w[documento nome titulo vencimento valor].freeze
    OPTIONAL = %w[telefone email contrato descricao papel].freeze
    MAX_BYTES = 50 * 1024 * 1024
    MAX_LINES = 200_000
    UNDEFINED_IN_WINDOWS_1252 = /[\x81\x8D\x8F\x90\x9D]/n

    Row = Data.define(:line, :values, :extra, :short)

    attr_reader :ignored_columns, :blank_lines

    def initialize(path, required: REQUIRED, optional: OPTIONAL)
      @path = path
      @required = required
      @optional = optional
      @ignored_columns = []
      @blank_lines = 0
      @columns = {}
      raise ImportRefused, "arquivo acima do limite de 50 MB" if File.size(path) > MAX_BYTES

      @latin1 = latin1?(File.binread(path, 1024 * 1024))
      read_header
    end

    # Cada linha do arquivo (o cabeçalho é a 1): `values` por coluna; `extra` quando há células preenchidas além do cabeçalho
    # e `short` quando faltam células.
    def each_row
      return enum_for(:each_row) unless block_given?

      count = 0
      line = 1
      csv = CSV.new(open_after_header, col_sep: ";", quote_char: '"', liberal_parsing: true)
      csv.each do |cells|
        line += 1
        if cells.empty? || cells.all?(&:blank?)
          @blank_lines += 1
          next
        end
        raise ImportRefused, "arquivo acima do limite de 200.000 linhas" if (count += 1) > MAX_LINES

        width = @columns.size
        extra = cells.drop(width).any?(&:present?)
        values = @columns.each_with_object({}) { |(position, name), hash| hash[name] = cells[position].to_s.strip }
        yield Row.new(line: line, values: values, extra: extra, short: cells.size < width)
      end
      raise ImportRefused, "arquivo sem linhas de dados" if count.zero?
    rescue CSV::MalformedCSVError, ArgumentError, Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
      raise ImportRefused, "arquivo ilegível: confira se é um CSV separado por ponto e vírgula, em UTF-8 ou Windows-1252"
    end

    private
      def latin1?(sample)
        raise ImportRefused, "o arquivo não parece ser um CSV (contém dados binários)" if sample.include?("\0")

        utf8 = sample.dup.force_encoding(Encoding::UTF_8)
        # Um corte no meio de um caractere multibyte da amostra não conta como erro.
        3.times { break if utf8.valid_encoding?; utf8 = utf8.byteslice(0, utf8.bytesize - 1).force_encoding(Encoding::UTF_8) }
        if utf8.valid_encoding?
          raise ImportRefused, "caracteres ilegíveis: confira se o arquivo foi salvo em UTF-8 ou Windows-1252" if utf8.include?("�")

          false
        else
          # Bytes que o Windows-1252 não define indicam outra codificação.
          raise ImportRefused, "caracteres ilegíveis: confira se o arquivo foi salvo em UTF-8 ou Windows-1252" if sample.b.match?(UNDEFINED_IN_WINDOWS_1252)

          true
        end
      end

      def open_file
        File.open(@path, @latin1 ? "rb:Windows-1252:UTF-8" : "rb:UTF-8").tap { |file| file.seek(3) if File.binread(@path, 3) == "\xEF\xBB\xBF".b }
      end

      def open_after_header
        io = open_file
        io.gets
        io
      end

      def read_header
        io = open_file
        header = io.gets
        io.close
        raise ImportRefused, "arquivo sem linhas de dados" if header.nil? || header.strip.empty?
        raise ImportRefused, 'separador errado: o arquivo usa vírgula. Salve como "CSV (separado por ponto e vírgula)".' if !header.include?(";") && header.include?(",")

        known = @required + @optional
        CSV.parse_line(header.chomp, col_sep: ";", quote_char: '"', liberal_parsing: true).each_with_index do |raw, position|
          name = FoldedText.fold(raw.to_s).delete(" ")
          if known.include?(name) && !@columns.value?(name)
            @columns[position] = name
          elsif raw.to_s.strip.present?
            @ignored_columns << raw.to_s.strip
          end
        end
        missing = @required - @columns.values
        raise ImportRefused, "coluna obrigatória ausente: #{missing.join(', ')}" if missing.any?
      end
  end
end
