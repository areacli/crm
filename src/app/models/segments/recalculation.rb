module Segments
  # Grava o segmento de cada contrato do credor e o histórico (R153): só onde mudou, tudo por conjunto, numa transação com trava por credor
  # para a carga e a tarefa diária não se atropelarem. Contrato que deixou de ter título em cobrança fica sem segmento (R152).
  class Recalculation
    NAME = "segments_recalculation"

    def initialize(tenant) = @tenant = tenant

    # Execução registrada por credor (O8); a falha de um credor fica no registro dele e não para os outros (R153, MT-19).
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

    # Devolve quantos contratos mudaram de segmento. Consulta: ver `Calculator`; escrita: `contracts (segment_id)` e `contract_segments`.
    def apply(today: Date.current)
      @tenant.association(:setting).reset
      proposal = Proposal.current(@tenant)
      calc = Calculator.new(@tenant, entries: proposal.entries, policy: proposal.policy, today: today).sql
      t = @tenant.id.to_i
      quoted_today = ActiveRecord::Base.connection.quote(today)
      ApplicationRecord.transaction do
        Portfolio::Sql.execute("select pg_advisory_xact_lock(2, ?)", t)
        Portfolio::Sql.execute("drop table if exists segment_calc")
        Portfolio::Sql.execute("create temporary table segment_calc on commit drop as #{calc}")
        Portfolio::Sql.execute(<<~SQL)
          insert into contract_segments (contract_id, segment_id, since)
          select contract_id, new_segment_id, #{quoted_today}::date from (
            select contract_id, new_segment_id from segment_calc where new_segment_id is distinct from old_segment_id
            union all
            select c.id, null from contracts c where c.tenant_id = #{t} and c.segment_id is not null
              and not exists (select 1 from segment_calc s where s.contract_id = c.id)
          ) changes
          on conflict (contract_id, since) do update set segment_id = excluded.segment_id
        SQL
        changed = Portfolio::Sql.run(<<~SQL)
          update contracts c set segment_id = s.new_segment_id from segment_calc s
          where c.id = s.contract_id and c.segment_id is distinct from s.new_segment_id
        SQL
        changed += Portfolio::Sql.run(<<~SQL)
          update contracts c set segment_id = null where c.tenant_id = #{t} and c.segment_id is not null
            and not exists (select 1 from segment_calc s where s.contract_id = c.id)
        SQL
        Portfolio::Sql.execute("drop table segment_calc")
        changed
      end
    end
  end
end
