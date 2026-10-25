module Portfolio
  # SQL em lote da importação (decisão 0004). Os valores entram pelo `sanitize_sql_array` do Active Record (citados com o tipo certo);
  # as instruções de criação de tabela temporária não aceitam parâmetros do servidor, e os valores são sempre números nossos.
  module Sql
    module_function

    def run(sql, *binds) = connection.exec_update(sanitize(sql, binds))

    def execute(sql, *binds) = connection.execute(sanitize(sql, binds))

    def one(sql, *binds) = connection.select_one(sanitize(sql, binds))

    def rows(sql, *binds) = connection.select_all(sanitize(sql, binds)).to_a

    def connection = ActiveRecord::Base.connection

    def sanitize(sql, binds) = binds.empty? ? sql : ActiveRecord::Base.sanitize_sql_array([ sql, *binds ])
  end
end
