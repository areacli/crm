# Protótipo do RLS (decisão 0024) antes de seguir a etapa 2 da camada 18: papel sem superusuário, políticas de leitura em clientes, contratos,
# ligação contrato × cliente e faturas, contexto por `set_config`, e as consultas do usuário de operação e da equipe do credor medidas com o
# RLS ligado. Tudo numa transação desfeita no fim: nada fica no banco. Nada disto roda em produção.
require_relative "../measure_data"

namespace :crm do
  desc "Protótipo do RLS (0024): crm:prototype_rls[contratos,distribuidos]"
  task :prototype_rls, %i[contracts distributed] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    Rails.logger.level = :info
    count = (args[:contracts].presence || 200_000).to_i
    distributed = (args[:distributed].presence || 50_000).to_i
    reuse = ENV["TENANT"].presence
    tenant = reuse ? Tenant.find(reuse) : Tenant.provision!("Protótipo RLS #{Time.current.strftime('%H%M%S')}")
    t = tenant.id
    conn = ActiveRecord::Base.connection
    measure = lambda do |label, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      puts format("%-76s %8.3f s  %s", label, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, result.is_a?(Array) ? result.first.inspect[0, 60] : "")
      result
    end

    unless reuse
      measure.call("massa: #{count} contratos, #{count * 3} títulos") do
        MeasureData.portfolio(t, count, bills_per: 3, bill: ->(i, n) { { number: "NF-#{i}/#{n}", due_date: Date.current - ((i * 37 + n * 11) % 500) + 60,
                                                                           amount_cents: 5000 + (i * 7919 + n * 131) % 250_000 } })
      end
      MeasureData.analyze(%w[customers contracts contract_customers bills])
    end

    conn.transaction do
      operation = Operation.create!(cnpj: "11444777000161", legal_name: "Recupera Cobranças Ltda", short_name: "Recupera")
      other = Operation.create!(cnpj: "11222333000181", legal_name: "Fale Mais Ltda", short_name: "Fale+")
      conn.execute(<<~SQL)
        insert into distributions (tenant_id, operation_id, contract_id, customer_id, exposure, starts_on, ends_on, ended_at, created_at, updated_at)
        select #{t}, case when n <= #{distributed} then #{operation.id} else #{other.id} end,
               case when n % 10 = 0 then null else c.id end,
               case when n % 10 = 0 then (select customer_id from contract_customers cc where cc.contract_id = c.id limit 1) end,
               case when n % 3 = 0 then 'all' else 'overdue' end, current_date - 10, current_date + 20,
               case when n % 10 = 5 then now() end, now(), now()
        from (select id, row_number() over (order by id) as n from contracts where tenant_id = #{t}) c
        where n <= #{distributed + distributed / 2}
      SQL
      conn.execute("analyze distributions")

      # O papel da aplicação: sem superusuário, sem BYPASSRLS, sem ser dono. As funções lêem o contexto declarado; sem ele, nada (falha fechada).
      conn.execute(<<~SQL)
        create role crm_app_prototype nologin;
        grant select on all tables in schema public to crm_app_prototype;
        create function crm_scope() returns text language sql stable as $$ select coalesce(current_setting('crm.scope', true), '') $$;
        create function crm_operation() returns bigint language sql stable as $$ select nullif(current_setting('crm.operation', true), '')::bigint $$;
        create function crm_cutoff() returns date language sql stable as $$ select nullif(current_setting('crm.cutoff', true), '')::date $$;
      SQL
      # Versão 2: o alcance fica numa tabela derivada (mantida a cada distribuição, carga e na tarefa diária, como o enquadramento financeiro),
      # e a política só pergunta "este contrato está na tabela da minha operação?" por índice.
      conn.execute(<<~SQL)
        create table operation_contracts (operation_id bigint not null, tenant_id bigint not null, contract_id bigint not null, all_due boolean not null,
                                          primary key (operation_id, contract_id));
        insert into operation_contracts
        select d.operation_id, d.tenant_id, x.contract_id, bool_or(d.exposure = 'all')
          from distributions d
          join lateral (select d.contract_id where d.contract_id is not null
                        union all select cc.contract_id from contract_customers cc where cc.customer_id = d.customer_id) x on true
         where d.ended_at is null and d.starts_on <= current_date and (d.ends_on is null or d.ends_on >= current_date)
         group by 1, 2, 3;
        analyze operation_contracts;
        grant select on operation_contracts to crm_app_prototype;
      SQL
      conn.execute(<<~SQL)
        create table operation_customers (operation_id bigint not null, customer_id bigint not null, primary key (operation_id, customer_id));
        insert into operation_customers select distinct oc.operation_id, cc.customer_id from operation_contracts oc join contract_customers cc on cc.contract_id = oc.contract_id;
        analyze operation_customers;
        grant select on operation_customers to crm_app_prototype;
      SQL
      # Versão 4: um papel por tipo de usuário. A equipe do credor tem a política "tudo"; a operação, a política sem OR (o banco pode transformar a
      # condição em junção); o papel de entrada não tem política nenhuma e não vê nada (falha fechada).
      conn.execute("create role crm_team_prototype nologin; create role crm_operation_prototype nologin; grant select on all tables in schema public to crm_team_prototype, crm_operation_prototype")
      policies = {
        "contracts" => "exists (select 1 from operation_contracts oc where oc.operation_id = crm_operation() and oc.contract_id = contracts.id)",
        "contract_customers" => "exists (select 1 from operation_contracts oc where oc.operation_id = crm_operation() and oc.contract_id = contract_customers.contract_id)",
        "customers" => "exists (select 1 from operation_customers ou where ou.operation_id = crm_operation() and ou.customer_id = customers.id)",
        "bills" => "exists (select 1 from operation_contracts oc where oc.operation_id = crm_operation() and oc.contract_id = bills.contract_id and (oc.all_due or bills.due_date < crm_cutoff()))"
      }
      policies.each do |table, condition|
        conn.execute("alter table #{table} enable row level security")
        conn.execute("create policy team_all on #{table} for select to crm_team_prototype using (true)")
        conn.execute("create policy operation_reach on #{table} for select to crm_operation_prototype using (#{condition})")
      end

      queries = {
        "clientes visíveis (contagem)" => "select count(*) from customers where tenant_id = #{t}",
        "clientes, página de 20 por nome" => "select id, name from customers where tenant_id = #{t} order by name limit 20",
        "busca por nome (ilike)" => "select id, name from customers where tenant_id = #{t} and name ilike 'Cliente 12%' order by name limit 20",
        "títulos visíveis: soma do saldo" => "select count(*), sum(amount_cents - paid_cents) from bills where tenant_id = #{t} and status = 'active'",
        "soma do saldo com junção explícita pelo alcance" => "select count(*), sum(b.amount_cents - b.paid_cents) from operation_contracts oc join bills b on b.contract_id = oc.contract_id where oc.operation_id = nullif(current_setting('crm.operation', true), '')::bigint and b.tenant_id = #{t} and b.status = 'active'",
        "busca por nome com junção explícita pelo alcance" => "select c.id, c.name from operation_customers ou join customers c on c.id = ou.customer_id where ou.operation_id = nullif(current_setting('crm.operation', true), '')::bigint and c.tenant_id = #{t} and c.name ilike 'Cliente 12%' order by c.name limit 20",
        "ficha: contratos e títulos de um cliente" => "select b.id from customers cu join contract_customers cc on cc.customer_id = cu.id join bills b on b.contract_id = cc.contract_id where cu.id = (select min(id) from customers where tenant_id = #{t})"
      }
      { "equipe do credor (papel da equipe)" => [ "crm_team_prototype", {} ],
        "operação (papel da operação)" => [ "crm_operation_prototype", { "crm.operation" => operation.id.to_s, "crm.cutoff" => (Date.current - 5).iso8601 } ],
        "sem papel (falha fechada)" => [ "crm_app_prototype", {} ] }.each do |label, (role, context)|
        puts "\n#{label}"
        conn.execute("set local role #{role}")
        conn.execute("select set_config('crm.scope', '', true), set_config('crm.operation', '', true), set_config('crm.cutoff', '', true)")
        context.each { |key, value| conn.exec_query("select set_config($1, $2, true)", "rls", [ key, value ]) }
        queries.each do |name, sql|
          measure.call("  #{name}") { conn.select_all(sql).rows }
          puts conn.select_all("explain (analyze, buffers off) #{sql}").rows.map(&:first).first(18).map { "      #{_1}" } if ENV["EXPLAIN"] == "1" && label.start_with?("opera")
        end
        conn.execute("reset role")
      end
      raise ActiveRecord::Rollback
    end
    unless ENV["KEEP"] == "1" || reuse
      MeasureData.wipe_portfolio(t)
      Membership.where(tenant_id: t).delete_all
      tenant.destroy
      puts "credor do protótipo apagado"
    end
  end
end
