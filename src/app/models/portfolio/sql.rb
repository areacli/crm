module Portfolio
  # SQL de leitura das importações e dos relatórios (decisão 0021, que substitui a 0004): contagens, junções e agregações de conjunto. Os valores entram
  # pelo `sanitize_sql_array` do Active Record (citados com o tipo certo). `run` e `execute` NÃO são caminho de escrita de entidade de domínio; sobraram só
  # para dois usos, listados no teste de arquitetura (`test/architecture/batch_processing_test.rb`): o recálculo derivado dos segmentos (regrava a tabela de
  # cálculo) e a anonimização da 07 (reescrita irreversível em conjunto). Todo o resto lê (`one`, `rows`).
  module Sql
    module_function

    # As escritas em SQL cru não passam pelo Active Record: o cache de consultas (ligado dentro de jobs e requisições) é limpo para a próxima leitura não ver o que ficou para trás.
    def run(sql, *binds) = connection.exec_update(sanitize(sql, binds)).tap { connection.clear_query_cache }

    def execute(sql, *binds) = connection.execute(sanitize(sql, binds)).tap { connection.clear_query_cache }

    def one(sql, *binds) = connection.select_one(sanitize(sql, binds))

    def rows(sql, *binds) = connection.select_all(sanitize(sql, binds)).to_a

    def connection = ActiveRecord::Base.connection

    def sanitize(sql, binds) = binds.empty? ? sql : ActiveRecord::Base.sanitize_sql_array([ sql, *binds ])
  end
end
