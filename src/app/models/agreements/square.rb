module Agreements
  # Praça do cliente (11, R249, M12): o município do endereço válido mais recentemente atualizado dele (06), casado com a lista do IBGE pelo nome
  # (sem acento e sem diferença de maiúsculas) e pela UF, sem CEP e sem serviço externo. Sem endereço válido valem só os dias nacionais; são duas
  # situações, com nome e ação próprios: sem endereço e endereço inválido (revisão 13).
  module Square
    module_function

    def address_of(customer)
      customer.contacts.where(kind: "address", status: "valid").order(updated_at: :desc, id: :desc).first
    end

    def municipality_for(customer) = municipality_of(address_of(customer))

    def municipality_of(address)
      return unless address&.city.present? && address.state.present?

      Municipality.find_by(state: address.state.to_s.upcase, name_key: FoldedText.fold(address.city))
    end

    def calendar_for(customer, today: Date.current)
      Calendar.for(municipality_for(customer), years: (today.year - 1)..(today.year + 3))
    end

    # As duas situações em que não há praça e valem só os dias nacionais (11, revisão 13), cada uma com a sua ação: `:no_address`, o cliente sem endereço
    # cadastrado (cadastrar um), e `:invalid_address`, o cliente que tem endereço e nenhum serve de praça (conferir e corrigir). O endereço com cidade
    # inexistente já entra inválido (06, R126a). nil com a praça reconhecida.
    def situation(customer, address = address_of(customer))
      return if municipality_of(address)

      customer.contacts.address.exists? ? :invalid_address : :no_address
    end

    # Condições SQL das opções do filtro "Endereço" da lista de clientes (AB9), uma por situação. Consultas: `customer_contacts (customer_id, kind, key)`; a
    # tabela de municípios tem o índice único (UF, nome).
    ANY_ADDRESS_SQL = "exists (select 1 from customer_contacts c where c.customer_id = customers.id and c.kind = 'address')".freeze
    SQUARE_SQL = <<~SQL.squish.freeze
      exists (
        select 1 from customer_contacts a join municipalities m on m.state = upper(a.state) and m.name_key = translate(lower(btrim(a.city)), '#{Portfolio::Query::ACCENTED}', '#{Portfolio::Query::PLAIN}')
        where a.id = (select c.id from customer_contacts c where c.customer_id = customers.id and c.kind = 'address' and c.status = 'valid'
                      order by c.updated_at desc, c.id desc limit 1))
    SQL
    SITUATION_SQL = { "no_address" => "not #{ANY_ADDRESS_SQL}", "invalid" => "#{ANY_ADDRESS_SQL} and not #{SQUARE_SQL}" }.freeze
  end
end
