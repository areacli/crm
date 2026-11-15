module Cadences
  # "Ainda vale?" (21, R438): todo executor pergunta antes de executar, e a régua responde por item. Vale se a régua está ligada, a ação continua na
  # célula, o sujeito está na mesma raia, o objeto continua no mesmo episódio e a coluna ainda é a última alcançada, com os dados de agora. O que não
  # vale mais é descartado com o motivo; no comando agrupado, o executor segue só com os itens que valem.
  #
  # Responde por um lote de comandos da mesma rodada de uma vez (a mesma conta da rodada, só para os sujeitos deles): uma conta por comando custava
  # 755 s na recriação da demonstração, com 7 dias de rodadas.
  class StillValid
    def self.call(command, items = nil, now: Time.current) = batch([ command ], now: now, items: items).fetch(command.id, [])

    # { id do comando => itens que valem }. Os comandos são da mesma rodada.
    def self.batch(commands, now: Time.current, items: nil) = new(commands, items, now).call

    def initialize(commands, items, now)
      @commands = commands
      @round = commands.first.round
      @cadence = @round.cadence.reload
      @items = (items || CadenceCommandItem.where(cadence_command_id: commands.map(&:id), state: Returns::OPEN)).includes(decision: [ :bill, { lane: :segment } ]).to_a
      @now = now
    end

    def call
      by_command = @items.group_by(&:cadence_command_id)
      return discard(by_command, I18n.t("cadences.still_valid.cadence_off"), "cadence_off") unless @cadence.enabled?

      removed = @commands.select { |command| command.action.removed? }.map(&:id)
      by_command.slice(*removed).each_value { |items| items.each { |item| Returns.discard(item, I18n.t("cadences.still_valid.action_removed"), "action_removed") } }
      alive = by_command.except(*removed)
      return {} if alive.empty?

      current = evaluate(alive.values.flatten)
      alive.transform_values do |items|
        items.select do |item|
          reason, kind = check(item.decision, current)
          next true if reason.nil?

          Returns.discard(item, reason, kind)
          false
        end
      end
    end

    private
      def discard(by_command, reason, kind)
        by_command.each_value { |items| items.each { |item| Returns.discard(item, reason, kind) } }
        {}
      end

      # A raia, o objeto e a coluna de cada sujeito, agora (a mesma conta da rodada, só para eles).
      def evaluate(items)
        ids = items.map { |item| @cadence.subject == "customers" ? item.decision.customer_id : item.decision.contract_id }.compact.uniq
        result = { lanes: {}, objects: {}, reached: {} }
        ApplicationRecord.transaction do
          Decision.new(@round, simulate: true, only_ids: ids, day: @now.to_date, refresh: true).call
          result[:lanes] = Portfolio::Sql.rows("select subject_id, lane_id from cadence_lane_calc").to_h { |row| [ row["subject_id"].to_i, row["lane_id"].to_i ] }
          result[:objects] = Portfolio::Sql.rows("select object_key, episode_key, state from cadence_obj where object_key is not null").index_by { |row| row["object_key"] }
          result[:reached] = Portfolio::Sql.rows("select object_key, column_id from cadence_reached").to_h { |row| [ row["object_key"], row["column_id"].to_i ] }
          %w[cadence_lane_calc cadence_obj cadence_reached].each { |table| ActiveRecord::Base.connection.drop_table(table, if_exists: true) }
        end
        result
      end

      def check(decision, current)
        subject_id = @cadence.subject == "customers" ? decision.customer_id : decision.contract_id
        lane_id = current[:lanes][subject_id]
        if lane_id != decision.cadence_lane_id
          lane = CadenceLane.find_by(id: lane_id)
          name = lane.nil? || lane_id.zero? ? I18n.t("cadences.still_valid.no_lane") : (lane.default? ? I18n.t("cadences.default_lane") : lane.segment&.name)
          return [ I18n.t("cadences.still_valid.moved_lane", lane: name), "moved_lane" ]
        end
        object = current[:objects][decision.object_key]
        return [ out_of_episode(decision), "out_of_episode" ] if object.nil? || object["state"] != "ok" || object["episode_key"] != decision.episode_key
        return [ I18n.t("cadences.still_valid.next_column"), "next_column" ] if current[:reached][decision.object_key] != decision.cadence_column_id

        nil
      end

      # "saiu do episódio: título pago às 9h01" quando o título do objeto foi pago; senão, o motivo geral.
      def out_of_episode(decision)
        paid = if decision.bill then decision.bill.reload.paid? ? decision.bill : nil
        elsif decision.contract_id then Bill.where(contract_id: decision.contract_id, status: "paid").order(updated_at: :desc).first
        end
        return I18n.t("cadences.still_valid.out_of_episode") unless paid && paid.updated_at > decision.created_at

        I18n.t("cadences.still_valid.paid", time: paid.updated_at.in_time_zone.strftime("%-Hh%M"))
      end
  end
end
