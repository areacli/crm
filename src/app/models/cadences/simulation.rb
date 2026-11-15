module Cadences
  # O que a próxima rodada da agenda faria com os dados de agora (21, R442, R443): roda os passos da rodada (decidir, priorizar e montar) para a
  # régua e para as outras ligadas no mesmo horário, numa transação que é desfeita no fim. Nada fica gravado: nem decisão, nem comando, nem
  # episódio. `prepare` aplica antes, dentro da mesma transação, o que se quer conferir (a mudança da régua ou do segmento).
  module Simulation
    Result = Data.define(:slot, :rows, :summary, :commands, :first_column, :middle, :skipped, :deprioritized)

    module_function

    def run(cadence, slot: nil, prepare: nil)
      result = nil
      ApplicationRecord.transaction(requires_new: true) do
        prepare&.call(cadence)
        cadence.reload
        slot ||= Schedule.next_slot(cadence)
        result = slot ? compute(cadence, slot) : empty
        raise ActiveRecord::Rollback
      end
      result
    end

    def empty = Result.new(slot: nil, rows: [], summary: {}, commands: 0, first_column: 0, middle: 0, skipped: 0, deprioritized: 0)

    def compute(cadence, slot)
      tenant = cadence.tenant
      peers = Cadence.where(tenant_id: tenant.id, enabled: true).where.not(id: cadence.id).select { |other| Schedule.slot(other, slot.to_date) == slot }
      ([ cadence ] + peers).each do |record|
        CadenceRound.find_or_create_by!(tenant_id: tenant.id, cadence_id: record.id, scheduled_for: slot)
      end
      # A conferência de "ligar" vê a régua como ligada (R442).
      Cadence.where(id: cadence.id).update_all(enabled: true)
      round_runner = Round.new(tenant, slot)
      round_runner.decide
      round = CadenceRound.find_by!(cadence_id: cadence.id, scheduled_for: slot)
      middle = middle_entries(round)
      round_runner.prioritize
      round_runner.build
      collect(round.reload, slot, middle)
    end

    # Ao ligar e ao incluir coluna (R442): quem entra pela primeira coluna da raia e quem entra no meio (já passou de colunas e recebe de uma vez a
    # última alcançada). Antes do disparo da montagem.
    def middle_entries(round)
      rows = Portfolio::Sql.rows(<<~SQL)
        select count(distinct d.object_key) filter (where d.cadence_column_id <> f.first_column) as middle,
               count(distinct d.object_key) filter (where d.cadence_column_id = f.first_column) as first_column
          from cadence_decisions d
          join (select a.cadence_lane_id, (array_agg(k.id order by k.offset_days))[1] as first_column
                  from cadence_actions a join cadence_columns k on k.id = a.cadence_column_id
                 where a.removed_at is null and k.removed_at is null group by 1) f on f.cadence_lane_id = d.cadence_lane_id
         where d.cadence_round_id = #{Integer(round.id)} and d.state = 'decided'
           and not exists (select 1 from cadence_firings x where x.cadence_id = d.cadence_id and x.object_key = d.object_key and x.episode_key = d.episode_key)
      SQL
      rows.first.transform_values(&:to_i)
    end

    def collect(round, slot, middle)
      rows = Portfolio::Sql.rows(<<~SQL)
        select d.cadence_lane_id as lane_id, d.cadence_column_id as column_id, d.cadence_action_id as action_id,
               count(distinct m.id) as commands, count(i.id) as items
          from cadence_decisions d
          left join cadence_command_items i on i.cadence_decision_id = d.id
          left join cadence_commands m on m.id = i.cadence_command_id
         where d.cadence_round_id = #{Integer(round.id)}
         group by 1, 2, 3
      SQL
      Result.new(slot: slot, rows: rows.map { |row| row.transform_values(&:to_i) }, summary: round.summary,
                 commands: CadenceCommand.where(cadence_round_id: round.id).count,
                 first_column: middle["first_column"], middle: middle["middle"], skipped: CadenceSkip.where(cadence_round_id: round.id).count,
                 deprioritized: CadenceDecision.where(cadence_round_id: round.id, state: "deprioritized").count)
    end
  end
end
