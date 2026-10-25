module Agreements
  # Praça do cliente (11, R249, M12): o município do endereço válido mais recentemente atualizado dele (06), casado com a lista do IBGE pelo nome
  # (sem acento e sem diferença de maiúsculas) e pela UF, sem CEP e sem serviço externo. Sem endereço, ou sem casar, valem só os dias nacionais.
  module Square
    module_function

    def address_of(customer)
      customer.contacts.where(kind: "address", status: "valid").order(updated_at: :desc, id: :desc).first
    end

    def municipality_for(customer)
      address = address_of(customer)
      return unless address&.city.present? && address.state.present?

      Municipality.find_by(state: address.state.to_s.upcase, name_key: FoldedText.fold(address.city))
    end

    def calendar_for(customer, today: Date.current)
      Calendar.for(municipality_for(customer), years: (today.year - 1)..(today.year + 3))
    end

    # "Cidade não reconhecida": o cliente sem endereço válido, ou cujo endereço mais recente não casou com o IBGE (AB9). Usada na ficha e no filtro da lista.
    def unrecognized?(customer) = municipality_for(customer).nil?

    # Condição SQL do filtro "cidade não reconhecida" da lista de clientes (AB9): o endereço válido mais recente do cliente não casa com nenhum município.
    # Consulta: `customer_contacts (customer_id, kind, key)`; a tabela de municípios tem o índice único (UF, nome).
    UNRECOGNIZED_SQL = <<~SQL.squish.freeze
      not exists (
        select 1 from customer_contacts a join municipalities m on m.state = upper(a.state) and m.name_key = translate(lower(btrim(a.city)), '#{Portfolio::Query::ACCENTED}', '#{Portfolio::Query::PLAIN}')
        where a.id = (select c.id from customer_contacts c where c.customer_id = customers.id and c.kind = 'address' and c.status = 'valid'
                      order by c.updated_at desc, c.id desc limit 1))
    SQL
  end
end
