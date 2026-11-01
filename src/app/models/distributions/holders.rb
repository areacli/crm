module Distributions
  # Com quem está cada contrato hoje, para a ficha da equipe do credor (14, R348): "com a Recupera desde 01/11/2026 (até 30/11/2026)",
  # pela distribuição do contrato ou de um cliente dele. Índices: `distributions (tenant_id, contract_id)` e `(tenant_id, customer_id)`.
  module Holders
    module_function

    def for_contracts(contract_ids)
      return {} if contract_ids.empty?

      customers = ContractCustomer.where(contract_id: contract_ids).pluck(:contract_id, :customer_id).group_by(&:last).transform_values { |rows| rows.map(&:first) }
      scope = Distribution.in_force.includes(:operation)
      rows = scope.where(contract_id: contract_ids).map { |distribution| [ distribution.contract_id, distribution ] }
      rows += scope.where(customer_id: customers.keys).flat_map { |distribution| customers.fetch(distribution.customer_id, []).map { |id| [ id, distribution ] } }
      rows.group_by(&:first).transform_values do |pairs|
        pairs.map(&:last).uniq.map do |distribution|
          text = "com a #{distribution.operation.short_name} desde #{distribution.starts_on.strftime('%d/%m/%Y')}"
          text += " (até #{distribution.ends_on.strftime('%d/%m/%Y')})" if distribution.ends_on
          text += distribution.source == "rule" ? ", pela regra" : (distribution.customer_id ? ", pelo cliente" : "")
          text
        end
      end
    end
  end
end
