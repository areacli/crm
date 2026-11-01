module Segments
  # Os clientes que um segmento pega, para o filtro da lista de clientes (13, R275; decisão 0023, opção 1): calculados na hora e guardados numa
  # tabela temporária da conexão, que a consulta da lista lê. Limite de 2 s: passando disso, a lista diz que o segmento demora demais para ela.
  module ListFilter
    TABLE = "segment_filter_customers"
    TIMEOUT = "2s"

    module_function

    # true quando carregou; false quando passou do tempo.
    def load(segment)
      matching = Compiler.new(segment.tenant).matching(segment.expression_object)
      select = segment.subject == "customers" ? "select m.id from (#{matching.sql}) m" : "select distinct cc.customer_id from contract_customers cc join (#{matching.sql}) m on m.id = cc.contract_id"
      connection = ActiveRecord::Base.connection
      connection.execute("create temporary table if not exists #{TABLE} (customer_id bigint primary key)")
      ActiveRecord::Base.transaction do
        connection.execute("truncate #{TABLE}")
        connection.execute("set local work_mem = '#{Compiler::WORK_MEM}'")
        connection.execute(ActiveRecord::Base.sanitize_sql_array([ "set local statement_timeout = ?", TIMEOUT ]))
        connection.exec_query("insert into #{TABLE} (customer_id) #{select}", "Segments", matching.binds)
      end
      true
    rescue ActiveRecord::QueryCanceled
      false
    end
  end
end
