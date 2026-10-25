module Payments
  # Grava as linhas da conferência de pagamentos ou estornos na tabela de preparação, em lote, pelo COPY do PostgreSQL.
  class Staging
    COLUMNS = %w[import_id line channel_code identifier document bill_number paid_on amount_cents payment_method payment_identifier reason ok].freeze

    def initialize(import_id, batch_size: 5000)
      @import_id = import_id
      @batch_size = batch_size
      @buffer = []
    end

    # `row` é uma linha normalizada de um dos dois validadores; o que ela não tem fica nulo.
    def add(row)
      values = row.to_h
      push [ @import_id, row.line, *COLUMNS[2..-2].map { |column| values[column.to_sym] }, "t" ]
    end

    def flush
      return if @buffer.empty?

      connection = ActiveRecord::Base.connection.raw_connection
      connection.copy_data("COPY payment_rows (#{COLUMNS.join(',')}) FROM STDIN") { @buffer.each { |line| connection.put_copy_data(line) } }
      @buffer.clear
    end

    private
      def push(values)
        @buffer << "#{values.map { |value| value.nil? ? '\N' : escape(value.to_s) }.join("\t")}\n"
        flush if @buffer.size >= @batch_size
      end

      def escape(value) = value.gsub(/[\\\t\n\r]/, "\\" => "\\\\", "\t" => "\\t", "\n" => "\\n", "\r" => "\\r")
  end
end
