module Cadences
  # As contagens das rodadas da lista (21, R435): comandos, itens por estado, puladas, despriorizados e parâmetro inativo, e o detalhe por raia,
  # coluna e ação com os motivos mais comuns. Contadas por consulta, então se atualizam com os retornos (plano técnico da camada 23, decisão 12).
  class RoundCounts
    Detail = Data.define(:lane, :column, :action, :commands, :states, :reasons)

    def initialize(rounds)
      ids = rounds.map(&:id)
      @commands = CadenceCommand.where(cadence_round_id: ids).group(:cadence_round_id).count
      @items = CadenceCommandItem.joins(:command).where(cadence_commands: { cadence_round_id: ids }).group("cadence_commands.cadence_round_id", :state).count
      @skips = CadenceSkip.where(cadence_round_id: ids).group(:cadence_round_id).count
      @decisions = CadenceDecision.where(cadence_round_id: ids).where.not(state: "decided").group(:cadence_round_id, :state).count
    end

    def commands(round) = @commands.fetch(round.id, 0)
    def items(round, state) = @items.fetch([ round.id, state ], 0)
    def skips(round) = @skips.fetch(round.id, 0)
    def decisions(round, state) = @decisions.fetch([ round.id, state ], 0)

    def details(round)
      items = CadenceCommandItem.joins(:decision).where(cadence_decisions: { cadence_round_id: round.id })
      states = items.group("cadence_decisions.cadence_action_id", :state).count
      reasons = items.where.not(reason: nil).group("cadence_decisions.cadence_action_id", :reason).count
      commands = CadenceCommand.where(cadence_round_id: round.id).group(:cadence_action_id).count
      actions = CadenceAction.where(id: states.keys.map(&:first).uniq).includes(:message_piece, :queue_task, :lane, :column).to_a
      actions.sort_by { |action| [ action.lane.position, action.column.offset_days, action.position ] }.map do |action|
        Detail.new(lane: action.lane, column: action.column, action: action, commands: commands.fetch(action.id, 0),
                   states: states.select { |(id, _), _| id == action.id }.transform_keys(&:last),
                   reasons: reasons.select { |(id, _), _| id == action.id }.transform_keys(&:last).sort_by { |_, count| -count }.first(2))
      end
    end
  end
end
