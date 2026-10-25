module Titular
  # Guarda automática (07, R136 a R139): quem já passou do prazo e quem passa nos próximos dias, por credor. O fim da última relação de um
  # cliente é o maior entre os fins dos contratos em que ele figura (R138a); sem nenhum fato, é a entrada dele na carteira. Quem tem relação
  # em aberto, está retido ou já foi anonimizado não entra. Um SQL de conjunto serve à previsão da página e à tarefa diária.
  module Retention
    module_function

    # Relação (Customer com as colunas extras ended_on e due_on) dos clientes que vencem até `within` dias a partir de `today`. Os retidos
    # não entram (a página os lista à parte).
    def due(tenant_ids, within: 0, today: Date.current)
      Customer.from(Arel.sql("(#{sql(tenant_ids, within, today)}) customers"))
    end

    def sql(tenant_ids, within, today)
      ids = tenant_ids.map(&:to_i).presence&.join(",") || "0"
      <<~SQL
        with #{Facts.sql(tenant_ids: tenant_ids)},
        pending_docs as (select distinct tenant_id, document from payments where tenant_id in (#{ids}) and status = 'pending'),
        ended as (
          select cu.id, cu.tenant_id, cu.name, coalesce(max(f.last_on), cu.created_at::date) as ended_on
          from customers cu
          left join contract_customers cc on cc.customer_id = cu.id
          left join facts f on f.contract_id = cc.contract_id
          where cu.tenant_id in (#{ids}) and cu.anonymized_at is null and cu.retained_at is null
            and not exists (select 1 from pending_docs pd where pd.tenant_id = cu.tenant_id and pd.document = cu.document)
          group by cu.id
          having not coalesce(bool_or(f.open), false)
        )
        select e.id, e.tenant_id, e.name, e.ended_on, (e.ended_on + make_interval(years => ts.retention_years))::date as due_on
        from ended e join tenant_settings ts on ts.tenant_id = e.tenant_id
        where (e.ended_on + make_interval(years => ts.retention_years))::date <= #{ActiveRecord::Base.connection.quote(today + within)}::date
      SQL
    end
  end
end
