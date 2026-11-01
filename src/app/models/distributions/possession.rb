module Distributions
  # Posse (14, R321): as operações para as quais o contrato da fatura estava na data do pagamento, pela distribuição do contrato ou de um
  # cliente dele. Gravada no pagamento aplicado, para a remuneração futura (OPD8).
  module Possession
    module_function

    def operation_ids(contract_id, on)
      return [] unless contract_id

      Operations::Context.system do
        scope = Distribution.where("starts_on <= ? AND (ends_on IS NULL OR ends_on >= ?) AND (ended_at IS NULL OR ended_at::date > ?)", on, on, on)
        scope.where(contract_id: contract_id)
             .or(scope.where(customer_id: ContractCustomer.where(contract_id: contract_id).select(:customer_id)))
             .distinct.pluck(:operation_id).sort
      end
    end
  end
end
