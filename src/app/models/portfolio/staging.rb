module Portfolio
  # Grava as linhas da conferência na tabela de preparação, em lote, pelo COPY do PostgreSQL.
  class Staging
    COLUMNS = %w[import_id line document number name name_key phone email contract due_date amount_cents description ok keep_document roles product penalty_cents interest_cents correction_cents other_cents].freeze

    def initialize(import_id, batch_size: 5000)
      @import_id = import_id
      @batch_size = batch_size
      @buffer = []
    end

    def add(row, name_key)
      push [ @import_id, row.line, row.document, row.number, row.name, name_key, row.phone, row.email, row.contract, row.due_date, row.amount_cents,
             row.description, "t", "f", row.roles, row.product, row.penalty_cents, row.interest_cents, row.correction_cents, row.other_cents ]
    end

    # Linha recusada, mas com documento e título legíveis: guarda a chave para o título não ser retirado (R15).
    def add_key_only(line, document, number)
      push [ @import_id, line, document, number, nil, nil, nil, nil, nil, nil, nil, nil, "f", "f", nil, nil, nil, nil, nil, nil ]
    end

    def flush
      return if @buffer.empty?

      connection = ActiveRecord::Base.connection.raw_connection
      connection.copy_data("COPY import_rows (#{COLUMNS.join(',')}) FROM STDIN") { @buffer.each { |line| connection.put_copy_data(line) } }
      @buffer.clear
    end

    private
      def push(values)
        @buffer << "#{values.map { |value| value.nil? ? '\N' : escape(value.to_s) }.join("\t")}\n"
        flush if @buffer.size >= @batch_size
      end

      # Escapa os caracteres especiais do formato texto do COPY.
      def escape(value) = value.gsub(/[\\\t\n\r]/, "\\" => "\\\\", "\t" => "\\t", "\n" => "\\n", "\r" => "\\r")
  end
end
