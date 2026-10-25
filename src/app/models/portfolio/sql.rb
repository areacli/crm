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
        rows.each { |row| raw.put_copy_data("#{row.map { |value| value.nil? ? '\N' : escape(value.to_s) }.join("\t")}\n") }
      end
    end

    def escape(value) = value.gsub(/[\\\t\n\r]/, "\\" => "\\\\", "\t" => "\\t", "\n" => "\\n", "\r" => "\\r")

    def connection = ActiveRecord::Base.connection

    def sanitize(sql, binds) = binds.empty? ? sql : ActiveRecord::Base.sanitize_sql_array([ sql, *binds ])
  end
end
