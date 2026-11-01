module Operations
  # Grava a trilha (14, R320) do usuário de operação da requisição: no credor do cliente, ou em cada credor em que ele é da operação (busca e
  # "não encontrado", que não têm credor). Para a equipe do credor não grava nada.
  module Trail
    module_function

    def record(kind, user:, customer: nil, query: nil, results: nil)
      operation_id = Context.operation_id or return
      tenant_ids = customer ? [ customer.tenant_id ] : user.memberships.usable.where(operation_id: operation_id).pluck(:tenant_id)
      tenant_ids.each do |tenant_id|
        OperationTrailEvent.create!(tenant_id: tenant_id, operation_id: operation_id, user: user, kind: kind, customer: customer,
                                    query_text: query.to_s.first(100).presence, results: results, created_at: Time.current)
      end
    end

    # Limpeza diária (DOS1): o que passou de 12 meses sai.
    def purge(tenant) = OperationTrailEvent.where(tenant_id: tenant.id).where(created_at: ...OperationTrailEvent::KEEP_FOR.ago).delete_all
  end
end
