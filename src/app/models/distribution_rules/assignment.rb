module DistributionRules
  # O primeiro item do enquadramento da distribuição que cada contrato atende (sem regra de entrada, 13, revisão 6) (14, R342, R343), numa tabela temporária
  # `dist_calc (contract_id, item_key)`; 0 é a equipe do credor. O cálculo é o do compilador da linguagem (decisão 0023).
  module Assignment
    module_function

    # `items`: [[chave, expressão do segmento]] em ordem.
    TABLES = %w[dist_calc dist_now dist_new].freeze

    def load(tenant, items, table: "dist_calc", today: Date.current)
      raise ArgumentError, "tabela temporária desconhecida: #{table}" unless TABLES.include?(table)

      query = Segments::Compiler.new(tenant, today: today).classify(items, default_id: 0)
      connection = ActiveRecord::Base.connection
      connection.execute("drop table if exists #{table}")
      connection.execute("create temporary table #{table} (contract_id bigint primary key, item_key bigint, balance_cents numeric)")
      connection.exec_query("insert into #{table} select contract_id, tier_id, balance_cents from (#{query.sql}) q", "DistributionRules", query.binds)
    end

    def items_of(tenant) = DistributionRuleItem.where(tenant: tenant).ordered.includes(:segment).map { |item| [ item.id, item.segment.expression_object ] }
  end
end
