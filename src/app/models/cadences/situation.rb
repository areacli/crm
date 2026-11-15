module Cadences
  # A situação na régua (21, R444), calculada na hora para o cliente e os contratos dele, por régua ligada: a raia, o momento, a última coluna
  # alcançada, se ela já disparou (quando e com qual comando) ou por que nada sai ("raia sem ações", "fora do episódio", "sem marco",
  # "despriorizado por <régua>"), e a próxima coluna com ação. A conta é a da rodada, só para esses sujeitos, numa transação desfeita.
  class Situation
    Row = Data.define(:cadence, :object_label, :lane_label, :moment, :reached, :fired_item, :reason, :next_column)

    def self.for(customer, cadences: nil) = new(customer, cadences).rows

    def initialize(customer, cadences)
      @customer = customer
      @cadences = cadences || Cadence.where(tenant_id: customer.tenant_id, enabled: true).by_priority.to_a
    end

    def rows
      @cadences.flat_map { |cadence| rows_of(cadence) }
    end

    private
      def rows_of(cadence)
        # Os ids saem com o alcance de quem pede (o usuário de operação só tem os contratos que estão pra ele, RLS); a conta, com o papel da equipe,
        # restrita a eles.
        ids = cadence.subject == "customers" ? [ @customer.id ] : ContractCustomer.where(customer_id: @customer.id).pluck(:contract_id)
        return [] if ids.empty?

        data = Operations::Context.system { evaluate(cadence, ids) }
        lanes = cadence.lanes.includes(:segment).index_by(&:id)
        columns = cadence.columns.to_a
        actions = cadence.live_actions.pluck(:cadence_lane_id, :cadence_column_id).to_set
        data[:objects].filter_map do |object|
          lane = lanes[data[:lanes][object["subject_id"].to_i]]
          build_row(cadence, object, lane, columns, actions, data[:reached][object["object_key"]])
        end
      end

      def evaluate(cadence, ids)
        round = CadenceRound.new(tenant: cadence.tenant, cadence: cadence, scheduled_for: Time.current)
        result = {}
        ApplicationRecord.transaction(requires_new: true) do
          Decision.new(round, simulate: true, only_ids: ids, day: Date.current, refresh: false).call
          result[:lanes] = Portfolio::Sql.rows("select subject_id, lane_id from cadence_lane_calc").to_h { |row| [ row["subject_id"].to_i, row["lane_id"].to_i ] }
          result[:objects] = Portfolio::Sql.rows("select * from cadence_obj order by contract_id nulls first, bill_id nulls first")
          result[:reached] = Portfolio::Sql.rows("select object_key, column_id from cadence_reached").to_h { |row| [ row["object_key"], row["column_id"].to_i ] }
          raise ActiveRecord::Rollback
        end
        result
      end

      def build_row(cadence, object, lane, columns, actions, reached_id)
        label = object_label(object)
        lane_label = lane.nil? ? I18n.t("cadences.still_valid.no_lane") : (lane.default? ? I18n.t("cadences.default_lane") : lane.segment&.name)
        return Row.new(cadence, label, lane_label, nil, nil, nil, I18n.t("cadences.situation.without_milestone"), nil) if object["state"] == "none"
        return Row.new(cadence, label, lane_label, nil, nil, nil, I18n.t("cadences.situation.out_of_episode"), nil) if object["state"] == "out"

        moment = object["moment"].to_i
        if lane && columns.none? { |column| actions.include?([ lane.id, column.id ]) }
          return Row.new(cadence, label, lane_label, moment, nil, nil, I18n.t("cadences.situation.lane_without_actions"), nil)
        end

        reached = columns.find { |column| column.id == reached_id }
        upcoming = lane && columns.find { |column| column.offset_days > moment && actions.include?([ lane.id, column.id ]) }
        fired = reached && last_item(cadence, object, reached)
        reason = if reached.nil? then I18n.t("cadences.situation.before_first_column")
        elsif fired.nil? then deprioritized(cadence, object) || I18n.t("cadences.situation.waiting")
        end
        Row.new(cadence, label, lane_label, moment, reached, fired, reason, upcoming)
      end

      def last_item(cadence, object, column)
        CadenceCommandItem.joins(:decision).includes(:command).where(cadence_decisions: { cadence_id: cadence.id, object_key: object["object_key"],
                                                                                          episode_key: object["episode_key"], cadence_column_id: column.id })
                          .order(:created_at).last
      end

      def deprioritized(cadence, object)
        decision = CadenceDecision.where(cadence_id: cadence.id, object_key: object["object_key"], state: "deprioritized").includes(:deprioritized_by_cadence).order(:created_at).last
        decision && I18n.t("cadences.situation.deprioritized", cadence: decision.deprioritized_by_cadence&.name)
      end

      def object_label(object)
        if object["bill_id"] then Bill.find_by(id: object["bill_id"]).then { |bill| "#{bill&.number} · #{bill&.contract&.code}" }
        elsif object["contract_id"] then Contract.find_by(id: object["contract_id"])&.code || I18n.t("cadences.contract_without_code")
        else I18n.t("cadences.situation.customer")
        end
      end
  end
end
