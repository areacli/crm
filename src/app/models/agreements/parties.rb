module Agreements
  # Os clientes dos contratos do acordo e o papel de cada um (11, R219a, R220a, MTD4, MT-15, MT-16): o termo vai ao responsável financeiro (os titulares,
  # se nenhum for declarado) e é aceito por ele ou por um titular, conforme a política "quem aceita".
  module Parties
    Party = Data.define(:customer, :contract, :roles)

    module_function

    # Todos os clientes dos contratos, com os papéis.
    def of(contracts)
      ContractCustomer.where(contract_id: contracts.map(&:id)).includes(:customer, :contract).map { |link| Party.new(link.customer, link.contract, Array(link.roles)) }
    end

    # Responsáveis financeiros: por contrato, os declarados; sem nenhum declarado, os titulares (MT-16). Sem nenhum papel, todos os clientes do contrato.
    def financial_responsibles(contracts)
      of(contracts).group_by(&:contract).flat_map do |_, parties|
        declared = parties.select { |party| party.roles.include?("financial_responsible") }
        holders = parties.select { |party| party.roles.include?("holder") }
        (declared.presence || holders.presence || parties).map(&:customer)
      end.uniq
    end

    # Quem pode aceitar, com o papel que vale (R220a): o responsável financeiro e, no padrão, os titulares.
    def acceptors(contracts, policy)
      parties = of(contracts)
      list = []
      financial_responsibles(contracts).each { |customer| list << [ customer, "financial_responsible" ] }
      if policy == "financial_or_holder"
        parties.select { |party| party.roles.include?("holder") }.each { |party| list << [ party.customer, "holder" ] unless list.any? { |customer, _| customer.id == party.customer.id } }
      end
      list.uniq { |customer, role| [ customer.id, role ] }
    end
  end
end
