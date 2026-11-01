# Medição do "está pra mim?" da especificação 14 (Operações), antes do plano técnico: a pergunta como consulta de conjunto sobre uma tabela de
# distribuições TEMPORÁRIA (o esquema ainda não existe), com N contratos e D distribuídos. Nada disto roda em produção nem grava tabela nova.
require_relative "../measure_data"

namespace :crm do
  desc "Mede o escopo 'está pra mim?' (14, R313): crm:measure_operations[contratos,distribuidos]"
  task :measure_operations, %i[contracts distributed] => :environment do |_task, args|
    abort "Recusado em produção." if Rails.env.production?

    Rails.logger.level = :info
    count = (args[:contracts].presence || 200_000).to_i
    distributed = (args[:distributed].presence || 50_000).to_i
    reuse = ENV["TENANT"].presence
    tenant = reuse ? Tenant.find(reuse) : Tenant.provision!("Medição de operações #{Time.current.strftime('%H%M%S')}")
    t = tenant.id
    conn = ActiveRecord::Base.connection
    measure = lambda do |label, &work|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = work.call
      puts format("%-72s %8.3f s", label, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
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
      # Distribuições: D contratos à operação 1 (90% por contrato, 10% pelo cliente), outros D/2 à operação 2; 10% encerradas.
      conn.execute(<<~SQL)
        create temporary table op_distributions (id bigserial primary key, tenant_id bigint not null, operation_id bigint not null,
          contract_id bigint, customer_id bigint, exposure varchar(10) not null, starts_on date not null, ends_on date, ended_at timestamptz) on commit drop
      SQL
      measure.call("distribuições: #{distributed} + #{distributed / 2}") do
        conn.execute(<<~SQL)
          insert into op_distributions (tenant_id, operation_id, contract_id, customer_id, exposure, starts_on, ends_on, ended_at)
          select #{t}, case when n <= #{distributed} then 1 else 2 end,
                 case when n % 10 = 0 then null else c.id end,
                 case when n % 10 = 0 then (select customer_id from contract_customers cc where cc.contract_id = c.id limit 1) end,
                 case when n % 3 = 0 then 'all' else 'overdue' end, current_date - 10, current_date + 20,
                 case when n % 10 = 5 then now() end
          from (select id, row_number() over (order by id) as n from contracts where tenant_id = #{t}) c
          where n <= #{distributed + distributed / 2}
        SQL
      end
      if ENV["INDEXES"] != "0"
        measure.call("índices parciais (vigentes)") do
          conn.execute("create index on op_distributions (operation_id, tenant_id, contract_id) where ended_at is null and contract_id is not null")
          conn.execute("create index on op_distributions (operation_id, tenant_id, customer_id) where ended_at is null and customer_id is not null")
        end
      end
      conn.execute("analyze op_distributions")

      reached = <<~SQL
        with reached as (
          select d.contract_id, d.exposure from op_distributions d
           where d.tenant_id = #{t} and d.operation_id = 1 and d.ended_at is null and d.contract_id is not null
             and d.starts_on <= current_date and (d.ends_on is null or d.ends_on >= current_date)
          union all
          select cc.contract_id, d.exposure from op_distributions d join contract_customers cc on cc.customer_id = d.customer_id
           where d.tenant_id = #{t} and d.operation_id = 1 and d.ended_at is null and d.customer_id is not null
             and d.starts_on <= current_date and (d.ends_on is null or d.ends_on >= current_date)
        ), contracts_reached as (select contract_id, bool_or(exposure = 'all') as all_due from reached group by contract_id)
      SQL
      cutoff = "current_date - 5"
      queries = {
        "contratos pra operação (contagem)" => "#{reached} select count(*) from contracts_reached",
        "clientes pra operação, página de 20 por nome" => <<~SQL,
          #{reached} select cu.id, cu.name from customers cu
           where cu.tenant_id = #{t} and exists (select 1 from contract_customers cc join contracts_reached r on r.contract_id = cc.contract_id where cc.customer_id = cu.id)
           order by cu.name limit 20
        SQL
        "busca por nome entre os clientes pra operação" => <<~SQL,
          #{reached} select cu.id, cu.name from customers cu
           where cu.tenant_id = #{t} and cu.name ilike 'Cliente 12%'
             and exists (select 1 from contract_customers cc join contracts_reached r on r.contract_id = cc.contract_id where cc.customer_id = cu.id)
           order by cu.name limit 20
        SQL
        "títulos expostos: soma do saldo (resumo)" => <<~SQL,
          #{reached} select count(*), sum(b.amount_cents - b.paid_cents) from bills b join contracts_reached r on r.contract_id = b.contract_id
           where b.tenant_id = #{t} and b.status = 'active' and (r.all_due or b.due_date < #{cutoff})
        SQL
        "um contrato está pra mim? (ficha)" => <<~SQL
          #{reached} select exists (select 1 from contracts_reached where contract_id = (select id from contracts where tenant_id = #{t} order by id offset 1234 limit 1))
        SQL
      }
      queries.each do |label, sql|
        measure.call(label) { conn.select_all(sql).to_a }
        next unless ENV["EXPLAIN"] == "1"

        puts conn.select_all("explain (analyze, buffers off) #{sql}").rows.map(&:first).first(25).map { "    #{_1}" }
      end
      raise ActiveRecord::Rollback
    end
    puts "Credor de medição: #{t} (TENANT=#{t} reaproveita a massa)." if ENV["KEEP"] == "1"
    unless ENV["KEEP"] == "1" || reuse
      MeasureData.wipe_portfolio(t)
      Membership.where(tenant_id: t).delete_all
      tenant.destroy
      puts "credor de medição apagado"
    end
  end
end
