module Demo
  class Dataset
    # Direitos do titular (07): um cliente anonimizado a pedido, um com exportação registrada e um retido da tarefa de guarda.
    module TitularSteps
      private
        def titular(tenant)
          closed = Portfolio::Sql.rows(<<~SQL, tenant.id).map { |row| row["customer_id"].to_i }
            select b.customer_id from bills b
            where b.tenant_id = ? and (select count(*) from contract_customers cc where cc.contract_id = b.contract_id) = 1
            group by b.customer_id having count(*) filter (where b.status <> 'paid') = 0 and count(*) >= 1
            order by b.customer_id desc limit 12
          SQL
          customers = Customer.where(id: closed).where(anonymized_at: nil).order(id: :desc).to_a
          anonymized = nil
          customers.each do |customer|
            Titular::Anonymizer.on_request(customer, actor: @manager, reason: "Pedido do titular, protocolo 2026-0412.", document: customer.document)
            anonymized = customer
            break
          rescue Titular::Refused
            next
          end
          exported = customers.find { |customer| customer.id != anonymized&.id }
          Change.record!(tenant_id: tenant.id, user: @manager, subject_type: "customer", subject_id: exported.id, event: "data_exported", note: "Pedido do titular por e-mail.", origin: "screen") if exported
          retained = customers.reverse.find { |customer| ![ anonymized&.id, exported&.id ].include?(customer.id) && !customer.reload.anonymized? }
          Titular::Retainer.new(@manager).retain(retained, "Em disputa judicial, não anonimizar.") if retained
        end
    end
  end
end
