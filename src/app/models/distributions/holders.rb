module Distributions
  # Com quem está cada contrato hoje, para a coluna "Operações" da ficha da equipe do credor (14, R348; padrões de interface, revisões 21 e 23),
  # pela distribuição do contrato ou de um cliente dele: só a etiqueta de cada operação (o período e a origem estão na linha do tempo,
  # `Distributions::Timeline`). Índices: `distributions (tenant_id, contract_id)` e `(tenant_id, customer_id)`.
  module Holders
    # Uma operação que cobra o contrato hoje: o nome curto (a etiqueta) e a razão social (para o leitor de tela e o título).
    Holder = Data.define(:name, :legal_name)

    module_function

    def for_contracts(contract_ids)
      return {} if contract_ids.empty?

      customers = ContractCustomer.where(contract_id: contract_ids).pluck(:contract_id, :customer_id).group_by(&:last).transform_values { |rows| rows.map(&:first) }
      scope = Distribution.in_force.includes(:operation)
      rows = scope.where(contract_id: contract_ids).map { |distribution| [ distribution.contract_id, distribution.operation ] }
      rows += scope.where(customer_id: customers.keys).flat_map { |distribution| customers.fetch(distribution.customer_id, []).map { |id| [ id, distribution.operation ] } }
      # Uma etiqueta por operação, mesmo quando ela cobra o contrato por mais de uma distribuição (o contrato e um cliente dele, ou vários clientes).
      rows.group_by(&:first).transform_values do |pairs|
        pairs.map(&:last).uniq.sort_by(&:short_name).map { |operation| Holder.new(operation.short_name, operation.legal_name) }
      end
    end
  end
end
