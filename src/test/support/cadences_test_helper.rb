# Réguas para os testes (21): régua ligada com raias, colunas e ações, e a rodada de um horário rodada passo a passo.
module CadencesTestHelper
  def make_piece(tenant, name = "Lembrete atraso", channel: "sms") = MessagePiece.find_or_create_by!(tenant: tenant, name: name, channel: channel)

  # `lanes`: [[segmento ou nil (trilha padrão), { offset => [ação, ...] }], ...], na ordem; a última é a trilha padrão. Ação: { kind:, piece:, ... }.
  def make_cadence(tenant, name: "Cobrança PF", milestone: "contract_arrears", lanes: [], time: "09:30", days: (0..6).to_a, enabled: true, **options)
    cadence = Cadence.create!({ tenant: tenant, name: name, milestone: milestone, schedule_days: days, schedule_time: time, valid_from: Date.current - 30 }.merge(options))
    columns = {}
    lanes.each do |segment, cells|
      lane = segment ? cadence.add_lane!(segment) : cadence.default_lane
      cells.each do |offset, actions|
        column = columns[offset] ||= cadence.columns.find_or_create_by!(offset_days: offset)
        actions.each_with_index do |spec, index|
          spec = spec.dup
          piece = spec.delete(:piece)
          CadenceAction.create!({ lane: lane, column: column, position: index + 1, kind: spec.delete(:kind) || "sms", message_piece: piece }.merge(spec))
        end
      end
    end
    cadence.update!(enabled: true, enabled_since: Time.current - 30.days) if enabled
    cadence
  end

  def slot_today(time = "09:30")
    hour, minute = time.split(":").map(&:to_i)
    Time.zone.local(Date.current.year, Date.current.month, Date.current.day, hour, minute)
  end

  # Cria a rodada (se preciso) e roda os quatro passos do horário, como o job faz.
  def run_rounds(tenant, slot = slot_today, cadences: Cadence.where(tenant: tenant, enabled: true))
    cadences.each { |cadence| CadenceRound.find_or_create_by!(tenant: tenant, cadence: cadence, scheduled_for: slot) }
    round = Cadences::Round.new(tenant, slot)
    round.decide
    round.prioritize
    round.build
    round.enqueue
    drop_cadence_temp_tables
    CadenceRound.where(tenant: tenant, scheduled_for: slot).index_by(&:cadence_id)
  end

  # As tabelas temporárias da rodada somem no commit; no teste, a transação não termina, e o pedido seguinte (com outro papel do banco) não poderia
  # recriá-las.
  def drop_cadence_temp_tables
    %w[cadence_lane_calc cadence_obj cadence_reached cadence_recipients episode_calc].each { |table| ActiveRecord::Base.connection.execute("drop table if exists #{table}") }
  end

  def items_of(cadence) = CadenceCommandItem.joins(:command).where(cadence_commands: { cadence_round_id: cadence.rounds.select(:id) })
end
