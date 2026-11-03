module Tiers
  # Grava o item do enquadramento financeiro de cada contrato do credor e o histórico (13, R268): só onde mudou, tudo por conjunto, numa
  # transação com trava por credor para a carga e a tarefa diária não se atropelarem. Todo contrato do credor é
  # enquadrado, sem regra de entrada (13, revisão 6). O cálculo é o do compilador da linguagem (decisão 0023), com todo valor como parâmetro.
  class Recalculation
    NAME = "segments_recalculation"

    def initialize(tenant) = @tenant = tenant

    # Execução registrada por credor (O8); a falha de um credor fica no registro dele e não para os outros (MT-19).
    def call(today: Date.current)
      run = TaskRun.create!(tenant: @tenant, name: NAME, started_at: Time.current)
      changed = apply(today: today)
      run.update!(status: :succeeded, finished_at: Time.current, processed: changed)
      run
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { tenant_id: @tenant.id })
      run&.update!(status: :failed, finished_at: Time.current, error_kind: error.class.name.demodulize)
      run
    ensure
      Broadcast.changed(@tenant)
    end

    # Devolve quantos contratos mudaram de item. Consulta: `Segments::Compiler#classify`; escrita: `contracts (tier_id)` e `contract_tiers`.
    def apply(today: Date.current)
      @tenant.association(:setting).reset
      proposal = Proposal.current(@tenant)
      query = Segments::Compiler.new(@tenant, today: today).classify(proposal.classified, default_id: proposal.catch_all_id)
      t = @tenant.id.to_i
      quoted_today = ActiveRecord::Base.connection.quote(today)
      ApplicationRecord.transaction do
        Portfolio::Sql.execute("select pg_advisory_xact_lock(2, ?)", t)
        Portfolio::Sql.execute("set local work_mem = '#{Segments::Compiler::WORK_MEM}'")
        Portfolio::Sql.execute("drop table if exists tier_calc")
        Portfolio::Sql.execute("create temporary table tier_calc (contract_id bigint primary key, tier_id bigint, balance_cents numeric, person_type text) on commit drop")
        ActiveRecord::Base.connection.exec_query("insert into tier_calc #{query.sql}", "Tiers", query.binds)
        Portfolio::Sql.execute(<<~SQL)
          insert into contract_tiers (contract_id, tier_id, since)
          select contract_id, new_tier_id, #{quoted_today}::date from (
            select s.contract_id, s.tier_id as new_tier_id from tier_calc s join contracts c on c.id = s.contract_id where c.tier_id is distinct from s.tier_id
            union all
            select c.id, null from contracts c where c.tenant_id = #{t} and c.tier_id is not null
              and not exists (select 1 from tier_calc s where s.contract_id = c.id)
          ) changes
          on conflict (contract_id, since) do update set tier_id = excluded.tier_id
        SQL
        changed = Portfolio::Sql.run(<<~SQL)
          update contracts c set tier_id = s.tier_id from tier_calc s
          where c.id = s.contract_id and c.tier_id is distinct from s.tier_id
        SQL
        changed += Portfolio::Sql.run(<<~SQL)
          update contracts c set tier_id = null where c.tenant_id = #{t} and c.tier_id is not null
            and not exists (select 1 from tier_calc s where s.contract_id = c.id)
        SQL
        Portfolio::Sql.execute("drop table tier_calc")
        changed
      end
    end
  end
end
