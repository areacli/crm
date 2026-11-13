module Portfolio
  # Identidade remota do cliente num lote da confirmação (17, R407 a R409a): a linha com `id_cliente` reaproveita a identidade daquele sistema ou a
  # cria para o cliente do documento. A identidade que aponta para cliente de outro documento só passa ao novo com a mudança confirmada na
  # conferência; sem isso, a linha não é aplicada. Consulta do lote: `customer_identities (tenant_id, external_id, source_system_id)`.
  class IdentityResolver
    Result = Struct.new(:by_line, :changes, :unapplied)

    UNCONFIRMED = "id de cliente com outro documento, não confirmado; a linha não foi aplicada".freeze

    def initialize(import)
      @tenant_id = import.tenant_id
      @system_id = import.source_system_id
    end

    # `rows`: as linhas válidas do lote; `customers`: os clientes do lote pelo documento.
    def call(rows, customers)
      result = Result.new({}, [], {})
      wanted = rows.select(&:external_customer_id)
      return result if wanted.empty?

      identities = CustomerIdentity.where(tenant_id: @tenant_id, source_system_id: @system_id, external_id: wanted.map(&:external_customer_id).uniq).index_by(&:external_id)
      wanted.each do |row|
        customer = customers.fetch(row.document)
        identity = identities[row.external_customer_id]
        if identity.nil?
          identity = identities[row.external_customer_id] =
            CustomerIdentity.create!(tenant_id: @tenant_id, source_system_id: @system_id, customer: customer, external_id: row.external_customer_id)
        elsif identity.customer_id != customer.id
          next result.unapplied[row.line] = UNCONFIRMED unless row.hold_confirmed && %w[identity both].include?(row.hold_kind)

          move(identity, customer, result)
        end
        result.by_line[row.line] = identity
      end
      result
    end

    private
      # R409a: a identidade passa ao novo documento, com histórico. O registro guarda os ids dos clientes, nunca nome nem documento (a anonimização
      # do titular não alcança o histórico da identidade). As ligações do cliente antigo deixam de citar a identidade que não é mais dele.
      def move(identity, customer, result)
        result.changes << [ identity, "customer_changed", { field: "customer", before: identity.customer_id.to_s, after: customer.id.to_s, origin: "load" } ]
        ContractCustomer.where(customer_id: identity.customer_id, customer_identity_id: identity.id).update_all(customer_identity_id: nil)
        identity.update!(customer: customer)
      end
  end
end
