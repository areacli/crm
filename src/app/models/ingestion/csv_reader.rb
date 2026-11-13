require "csv"

module Ingestion
  # Leitor de CSV (decisão 0031): separador `;`, UTF-8 ou Windows-1252, cabeçalho obrigatório com as colunas em qualquer ordem, sem diferenciar
  # maiúsculas nem acentos (formato da planilha, especificação 01). Lê registro a registro, sem carregar o arquivo inteiro. Conhece só o formato:
  # quem diz quais colunas existem é quem chama, e as regras ficam nos validadores.
  class CsvReader
    MAX_BYTES = 50 * 1024 * 1024
    MAX_LINES = 200_000
    UNDEFINED_IN_WINDOWS_1252 = /[\x81\x8D\x8F\x90\x9D]/n

    attr_reader :ignored_columns, :blank_lines

    def initialize(path, required:, optional:)
      @path = path
      @required = required
      @optional = optional
      @ignored_columns = []
      @blank_lines = 0
      @columns = {}
      raise Portfolio::ImportRefused, "arquivo acima do limite de 50 MB" if File.size(path) > MAX_BYTES

      @latin1 = latin1?(File.binread(path, 1024 * 1024))
      read_header
    end

    # Estimativa de quantos registros o arquivo tem, para o progresso, sem contar as linhas.
    def estimated_total(bytes_per_line:) = [ File.size(@path) / bytes_per_line, 1 ].max

    # Cada linha do arquivo (o cabeçalho é a 1): `values` por coluna; `extra` quando há células preenchidas além do cabeçalho
    # e `short` quando faltam células.
    def each_record
      return enum_for(:each_record) unless block_given?

      count = 0
      line = 1
      csv = CSV.new(open_after_header, col_sep: ";", quote_char: '"', liberal_parsing: true)
      csv.each do |cells|
        line += 1
        if cells.empty? || cells.all?(&:blank?)
          @blank_lines += 1
          next
        end
        raise Portfolio::ImportRefused, "arquivo acima do limite de 200.000 linhas" if (count += 1) > MAX_LINES

        # A largura é a do cabeçalho, com as colunas ignoradas: a célula de uma coluna ignorada não é célula a mais, e a linha só é curta quando
        # não chega à última coluna conhecida.
        extra = cells.drop(@width).any?(&:present?)
        values = @columns.each_with_object({}) { |(position, name), hash| hash[name] = cells[position].to_s.strip }
        yield RawRecord.new(position: line, values: values, extra: extra, short: cells.size <= @last_known)
      end
      raise Portfolio::ImportRefused, "arquivo sem linhas de dados" if count.zero?
    rescue CSV::MalformedCSVError, ArgumentError, Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
      raise Portfolio::ImportRefused, "arquivo ilegível: confira se é um CSV separado por ponto e vírgula, em UTF-8 ou Windows-1252"
    end

    private
      def latin1?(sample)
        raise Portfolio::ImportRefused, "o arquivo não parece ser um CSV (contém dados binários)" if sample.include?("\0")

        utf8 = sample.dup.force_encoding(Encoding::UTF_8)
        # Um corte no meio de um caractere multibyte da amostra não conta como erro.
        3.times { break if utf8.valid_encoding?; utf8 = utf8.byteslice(0, utf8.bytesize - 1).force_encoding(Encoding::UTF_8) }
        if utf8.valid_encoding?
          raise Portfolio::ImportRefused, "caracteres ilegíveis: confira se o arquivo foi salvo em UTF-8 ou Windows-1252" if utf8.include?("�")

          false
        else
          # Bytes que o Windows-1252 não define indicam outra codificação.
          raise Portfolio::ImportRefused, "caracteres ilegíveis: confira se o arquivo foi salvo em UTF-8 ou Windows-1252" if sample.b.match?(UNDEFINED_IN_WINDOWS_1252)

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
        raise Portfolio::ImportRefused, "arquivo sem linhas de dados" if header.nil? || header.strip.empty?
        raise Portfolio::ImportRefused, 'separador errado: o arquivo usa vírgula. Salve como "CSV (separado por ponto e vírgula)".' if !header.include?(";") && header.include?(",")

        known = @required + @optional
        cells = CSV.parse_line(header.chomp, col_sep: ";", quote_char: '"', liberal_parsing: true)
        @width = (cells.rindex { |raw| raw.to_s.strip.present? } || -1) + 1
        cells.each_with_index do |raw, position|
          name = FoldedText.fold(raw.to_s).delete(" ")
          if known.include?(name) && !@columns.value?(name)
            @columns[position] = name
          elsif raw.to_s.strip.present?
            @ignored_columns << raw.to_s.strip
          end
        end
        missing = @required - @columns.values
        raise Portfolio::ImportRefused, "coluna obrigatória ausente: #{missing.join(', ')}" if missing.any?

        @last_known = @columns.keys.max || 0
      end
  end
end
