module Portfolio
  # SQL em lote da importação (decisão 0004). Os valores entram pelo `sanitize_sql_array` do Active Record (citados com o tipo certo);
  # as instruções de criação de tabela temporária não aceitam parâmetros do servidor, e os valores são sempre números nossos.
  module Sql
    module_function

    def run(sql, *binds) = connection.exec_update(sanitize(sql, binds))

    def execute(sql, *binds) = connection.execute(sanitize(sql, binds))

    def one(sql, *binds) = connection.select_one(sanitize(sql, binds))

    def rows(sql, *binds) = connection.select_all(sanitize(sql, binds)).to_a

    # Grava linhas (arrays de valores, na ordem de `columns`) pelo COPY do PostgreSQL: bem mais rápido que o INSERT em lote do Active
    # Record, que converte cada valor em Ruby (medido na V4 de pagamentos: 200 mil pagamentos). Violação de chave é erro, como no `insert_all!`.
    def copy_in(table, columns, rows)
      return if rows.empty?

      raw = connection.raw_connection
      raw.copy_data("COPY #{table} (#{columns.join(',')}) FROM STDIN") do
        # Linhas juntas num buffer de cerca de 1 MB: uma chamada por linha custava mais que o resto do recálculo dos encargos (80 mil linhas em 1,9 s).
        buffer = +""
        rows.each do |row|
          row.each_with_index do |value, index|
            buffer << "\t" if index.positive?
            buffer << (value.nil? ? '\N' : cell(value))
          end
          buffer << "\n"
          next if buffer.bytesize < 1_048_576

          raw.put_copy_data(buffer)
          buffer.clear
        end
        raw.put_copy_data(buffer) unless buffer.empty?
      end
    end

    # Número e data não precisam de escape; o texto só quando traz tabulação, barra ou quebra de linha.
    def cell(value)
      return value.to_s if value.is_a?(Integer)

      text = value.to_s
      text.match?(/[\\\t\n\r]/) ? escape(text) : text
    end

    def escape(value) = value.gsub(/[\\\t\n\r]/, "\\" => "\\\\", "\t" => "\\t", "\n" => "\\n", "\r" => "\\r")

    def connection = ActiveRecord::Base.connection

    def sanitize(sql, binds) = binds.empty? ? sql : ActiveRecord::Base.sanitize_sql_array([ sql, *binds ])
  end
end
