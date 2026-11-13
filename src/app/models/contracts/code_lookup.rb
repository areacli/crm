module Contracts
  # 17, R421: o código do contrato é único dentro do sistema, não do credor. Onde uma pessoa digita o código (distribuição, transferência de crédito), ele pode
  # casar com mais de um contrato, um por sistema: a tela lista os encontrados, com sistema e clientes, e a pessoa escolhe (SI4). O contrato escolhido só vale
  # se for um dos encontrados com aquele código: trocar o código depois de escolher volta à pergunta.
  class CodeLookup
    attr_reader :contracts

    def initialize(tenant_id, code, chosen_id = nil)
      code = code.to_s.strip
      @contracts = code.empty? ? [] : Contract.where(tenant_id: tenant_id, code: code).includes(:source_system, :customers).order(:id).to_a
      @chosen = @contracts.find { |contract| contract.id == chosen_id.to_i } if chosen_id.present?
    end

    # O contrato do código: o escolhido ou o único. `nil` quando não há nenhum ou quando falta escolher.
    def contract = @chosen || (@contracts.first if @contracts.one?)

    def ambiguous? = @contracts.size > 1 && @chosen.nil?

    # Rótulo de cada encontrado na escolha: código, sistema e clientes.
    def self.option(contract)
      names = contract.customers.map(&:name).sort
      people = names.size > 3 ? "#{names.first(3).join(', ')} e mais #{names.size - 3}" : names.to_sentence
      [ contract.label, contract.source_system.name, people ].compact_blank.join(" · ")
    end
  end
end
