module Queues
  # Dados de apoio da ordem das filas (15, R355), um por sujeito: saldo vencido e maior atraso (títulos em cobrança vencidos), o último
  # acionamento, o retorno do último acionamento e a última promessa quebrada. Do contrato; do cliente, somando ou pegando o maior dos
  # contratos dele e os acionamentos dele.
  module SortData
    module_function

    def sql(subject, tenant, today)
      subject == "customers" ? customers(tenant, today) : contracts(tenant, today)
    end

    def overdue(tenant, today)
      "select b.contract_id, sum(greatest(b.amount_cents - b.paid_cents, 0)) as balance, max(#{today}::date - b.due_date) as days " \
        "from bills b where b.tenant_id = #{tenant} and b.status = 'active' and b.due_date < #{today}::date group by b.contract_id"
    end

    def broken(tenant) = "select contract_id, max(closed_at) as at from payment_promises where tenant_id = #{tenant} and state = 'broken' group by contract_id"

    def contracts(tenant, today)
      <<~SQL
        select c.id, o.balance as overdue_balance, o.days as overdue_days, a.last_contact, lr.return_at, p.at as broken_at
          from contracts c
          left join (#{overdue(tenant, today)}) o on o.contract_id = c.id
          left join (select cc.contract_id, max(x.contacted_at) as last_contact from contact_attempts x join contract_customers cc on cc.customer_id = x.customer_id
                      where x.tenant_id = #{tenant} and (x.contract_id is null or x.contract_id = cc.contract_id) group by cc.contract_id) a on a.contract_id = c.id
          left join (#{Segments::Compiler::Bases.last_return_of_contracts(tenant)}) lr on lr.contract_id = c.id
          left join (#{broken(tenant)}) p on p.contract_id = c.id
         where c.tenant_id = #{tenant}
      SQL
    end

    def customers(tenant, today)
      <<~SQL
        select cu.id, k.balance as overdue_balance, k.days as overdue_days, a.last_contact, lr.return_at, k.broken_at
          from customers cu
          left join (select cc.customer_id, sum(o.balance) as balance, max(o.days) as days, max(p.at) as broken_at from contract_customers cc
                      left join (#{overdue(tenant, today)}) o on o.contract_id = cc.contract_id left join (#{broken(tenant)}) p on p.contract_id = cc.contract_id
                      group by cc.customer_id) k on k.customer_id = cu.id
          left join (select customer_id, max(contacted_at) as last_contact from contact_attempts where tenant_id = #{tenant} group by customer_id) a on a.customer_id = cu.id
          left join (select distinct on (customer_id) customer_id, return_at from contact_attempts where tenant_id = #{tenant} order by customer_id, contacted_at desc, id desc) lr on lr.customer_id = cu.id
         where cu.tenant_id = #{tenant}
      SQL
    end
  end
end
