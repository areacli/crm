module Cadences
  # A prioridade entre réguas e a montagem dos comandos de uma rodada (21, R436; plano técnico da camada 23, etapas "priorizar" e "enfileirar").
  # SQL de conjunto e idempotente: montar de novo na retomada não repete comando nem item (chaves únicas), e o disparo é gravado com o item.
  module Commands
    module_function

    # R436 (Q2, RED7): entre as rodadas do credor no mesmo horário, o mesmo tipo para o mesmo objeto fica com a régua de maior prioridade; as outras
    # decisões viram "elegível despriorizado", com a régua que ganhou, e não vão à fila (a régua que perdeu tenta de novo na rodada seguinte, Q1).
    def prioritize(round_ids)
      ids = sql_ids(round_ids)
      Portfolio::Sql.run(<<~SQL)
        update cadence_decisions d set state = 'deprioritized', deprioritized_by_cadence_id = w.winner
          from (
            select x.id, x.cadence_id, first_value(x.cadence_id) over (partition by x.kind, x.object_key order by k.position, k.id) as winner
              from cadence_decisions x join cadences k on k.id = x.cadence_id
             where x.cadence_round_id = any(#{ids}) and x.state = 'decided'
          ) w
         where d.id = w.id and w.cadence_id <> w.winner
      SQL
    end

    # Os comandos da rodada (R436): as comunicações da mesma ação para o mesmo destinatário viram um comando, com um item por objeto; o destinatário
    # é o cliente (régua de clientes) ou cada responsável financeiro do contrato, ou os titulares sem responsável (régua de contratos). As outras ações
    # têm um comando por objeto. O disparo (R434) é gravado junto, uma vez por episódio.
    def build(round)
      r = Integer(round.id)
      t = Integer(round.tenant_id)
      communications = Catalog::COMMUNICATIONS.keys.map { |kind| ActiveRecord::Base.connection.quote(kind) }.join(", ")
      Portfolio::Sql.execute("drop table if exists cadence_recipients")
      Portfolio::Sql.execute(<<~SQL)
        create temporary table cadence_recipients on commit drop as
        select d.id as decision_id, coalesce(d.customer_id, p.customer_id) as recipient
          from cadence_decisions d
          left join (
            select cc.contract_id, cc.customer_id,
                   jsonb_exists(cc.roles, 'financial_responsible') as fr,
                   (jsonb_exists(cc.roles, 'holder') or cc.roles = '[]'::jsonb) as holder,
                   bool_or(jsonb_exists(cc.roles, 'financial_responsible')) over (partition by cc.contract_id) as has_fr
              from contract_customers cc
             where cc.contract_id in (select contract_id from cadence_decisions where cadence_round_id = #{r} and contract_id is not null)
          ) p on d.customer_id is null and p.contract_id = d.contract_id and (p.fr or (not p.has_fr and p.holder))
         where d.cadence_round_id = #{r} and d.state = 'decided' and d.kind in (#{communications})
      SQL
      Portfolio::Sql.run(<<~SQL)
        insert into cadence_commands (tenant_id, cadence_round_id, cadence_action_id, kind, group_key, recipient_customer_id, state, created_at, updated_at)
        select distinct #{t}, #{r}, d.cadence_action_id, d.kind, 'a' || d.cadence_action_id || ':r' || x.recipient, x.recipient, 'queued', now(), now()
          from cadence_recipients x join cadence_decisions d on d.id = x.decision_id where x.recipient is not null
        union all
        select #{t}, #{r}, d.cadence_action_id, d.kind, 'd' || d.id, null, 'queued', now(), now()
          from cadence_decisions d where d.cadence_round_id = #{r} and d.state = 'decided' and d.kind not in (#{communications})
        on conflict (cadence_round_id, group_key) do nothing
      SQL
      Portfolio::Sql.run(<<~SQL)
        insert into cadence_command_items (cadence_command_id, cadence_decision_id, contract_id, customer_id, bill_id, state, created_at, updated_at)
        select m.id, d.id, d.contract_id, coalesce(d.customer_id, x.recipient), d.bill_id, 'queued', now(), now()
          from cadence_recipients x join cadence_decisions d on d.id = x.decision_id
          join cadence_commands m on m.cadence_round_id = #{r} and m.group_key = 'a' || d.cadence_action_id || ':r' || x.recipient
        union all
        select m.id, d.id, d.contract_id, d.customer_id, d.bill_id, 'queued', now(), now()
          from cadence_decisions d join cadence_commands m on m.cadence_round_id = #{r} and m.group_key = 'd' || d.id
         where d.cadence_round_id = #{r} and d.state = 'decided'
        on conflict (cadence_command_id, cadence_decision_id) do nothing
      SQL
      Portfolio::Sql.run(<<~SQL)
        insert into cadence_firings (cadence_id, object_key, episode_key, cadence_column_id, cadence_round_id, created_at)
        select distinct d.cadence_id, d.object_key, d.episode_key, d.cadence_column_id, #{r}, now()
          from cadence_decisions d where d.cadence_round_id = #{r} and exists (select 1 from cadence_command_items i where i.cadence_decision_id = d.id)
        on conflict do nothing
      SQL
      Portfolio::Sql.execute("drop table cadence_recipients")
    end

    # Põe na fila do executor os comandos ainda não postos (R435: a retomada põe o que faltou). O job leva só o id (a fila entrega ao menos uma vez,
    # e o executor reserva o comando antes de agir). O prazo de retorno conta da entrada na fila (R437a).
    def enqueue(round_ids, batch: 1000)
      total = 0
      loop do
        commands = CadenceCommand.where(cadence_round_id: round_ids, enqueued_at: nil).order(:id).limit(batch).includes(round: :cadence).to_a
        break if commands.empty?

        ActiveJob.perform_all_later(commands.map { |command| CadenceCommandJob.new(command.id) })
        now = Time.current
        commands.group_by { |command| [ command.round.cadence, command.kind ] }.each do |(cadence, kind), group|
          CadenceCommand.where(id: group.map(&:id)).update_all(enqueued_at: now, deadline_at: now + Catalog.return_hours(cadence, kind).hours, updated_at: now)
        end
        total += commands.size
        yield commands.last.id if block_given?
      end
      total
    end

    def sql_ids(ids) = "'{#{Array(ids).map { |id| Integer(id) }.join(',')}}'::bigint[]"
  end
end
