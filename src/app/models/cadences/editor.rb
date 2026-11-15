module Cadences
  # As mudanças da régua (21, R428 a R433, R437, R437a, R442), como operações: valem na hora na régua desligada; na ligada, passam pela conferência
  # (`Proposal`, `Review`, `Applier`), menos desligar, que vale na hora. Cada uma fica no histórico, com quem, quando, antes e depois (PD4).
  #
  # Operação: { "op" => nome, ... }:
  #   update (name, schedule_days, schedule_time, skip_national_holidays, valid_from, valid_until, return_hours), enable, disable,
  #   add_lane (segment_id, at), remove_lane (lane_id), move_lane (lane_id, to), add_column (offset), remove_column (column_id),
  #   add_action (lane_id, column_id, kind, params, message_piece_id, queue_task_id, payment_method), remove_action (action_id), move_priority (to).
  class Editor
    class Invalid < StandardError; end

    UPDATABLE = %w[name schedule_days schedule_time skip_national_holidays valid_from valid_until return_hours].freeze
    DIRECT = %w[disable].freeze

    def initialize(cadence, actor:) = (@cadence = cadence; @actor = actor)

    # Precisa de conferência: régua ligada e alguma operação além de desligar (R442).
    def self.needs_review?(cadence, operations) = (cadence.enabled? && operations.any? { |op| !DIRECT.include?(op["op"]) }) || operations.any? { |op| op["op"] == "enable" }

    def apply!(operations)
      ApplicationRecord.transaction do
        operations.each { |op| send("op_#{op.fetch('op')}", op.stringify_keys) }
        @cadence.increment!(:version)
      end
      @cadence
    rescue ActiveRecord::RecordInvalid => error
      raise Invalid, error.record.errors.full_messages.to_sentence
    end

    private
      def log(event, field: nil, before: nil, after: nil, subject: @cadence)
        Change.record!(subject, event, tenant_id: @cadence.tenant_id, actor: @actor, field: field, before: before&.to_s, after: after&.to_s)
      end

      def op_update(op)
        changes = op.slice(*UPDATABLE)
        before = @cadence.attributes.slice(*changes.keys)
        @cadence.update!(changes)
        changes.each_key { |field| log("updated", field: field, before: before[field], after: @cadence[field]) if before[field] != @cadence[field] }
      end

      def op_enable(_op)
        @cadence.update!(enabled: true, disabled_reason: nil)
        log("enabled", field: "enabled", before: false, after: true)
      end

      def op_disable(op)
        @cadence.update!(enabled: false, disabled_reason: op["reason"])
        log("disabled", field: "enabled", before: true, after: false)
      end

      def op_add_lane(op)
        segment = Segment.find_by!(id: op["segment_id"], tenant_id: @cadence.tenant_id)
        lane = @cadence.add_lane!(segment, at: op["at"])
        log("lane_added", field: "lanes", after: "#{lane.position}. #{segment.name}")
      end

      def op_remove_lane(op)
        lane = lane(op["lane_id"])
        raise Invalid, I18n.t("cadences.errors.default_lane") if lane.default?

        lane.update!(removed_at: Time.current)
        renumber_lanes
        log("lane_removed", field: "lanes", before: lane.segment&.name)
      end

      def op_move_lane(op)
        lane = lane(op["lane_id"])
        raise Invalid, I18n.t("cadences.errors.default_lane") if lane.default?

        fixed = @cadence.lanes.reload.reject(&:default?)
        fixed.delete(lane)
        fixed.insert((op["to"].to_i - 1).clamp(0, fixed.size), lane)
        fixed.each_with_index { |item, index| item.update!(position: index + 1) }
        @cadence.default_lane.update!(position: fixed.size + 1)
        log("lane_moved", field: "lanes", after: "#{op['to']}. #{lane.segment&.name}")
      end

      def op_add_column(op)
        column = @cadence.columns.create!(offset_days: op["offset"])
        log("column_added", field: "columns", after: column.label)
      end

      def op_remove_column(op)
        column = @cadence.columns.find(op["column_id"])
        column.update!(removed_at: Time.current)
        column.actions.update_all(removed_at: Time.current)
        log("column_removed", field: "columns", before: column.label)
      end

      def op_add_action(op)
        lane = lane(op["lane_id"])
        column = @cadence.columns.find(op["column_id"])
        position = (lane.actions.where(cadence_column_id: column.id).maximum(:position) || 0) + 1
        action = CadenceAction.create!(lane: lane, column: column, position: position, kind: op["kind"], params: op["params"] || {},
                                       message_piece_id: op["message_piece_id"], queue_task_id: op["queue_task_id"], payment_method: op["payment_method"])
        log("action_added", field: "actions", after: "#{lane.position} × #{column.label}: #{Labels.action(action)}")
      end

      def op_remove_action(op)
        action = CadenceAction.joins(:lane).where(cadence_lanes: { cadence_id: @cadence.id }).find(op["action_id"])
        action.update!(removed_at: Time.current)
        log("action_removed", field: "actions", before: "#{action.lane.position} × #{action.column.label}: #{Labels.action(action)}")
      end

      # A prioridade é a posição na lista do credor (R428): a régua vai para `to`, e as outras se ajeitam.
      def op_move_priority(op)
        list = Cadence.where(tenant_id: @cadence.tenant_id).by_priority.to_a
        before = @cadence.position
        list.delete(@cadence)
        list.insert((op["to"].to_i - 1).clamp(0, list.size), @cadence)
        list.each_with_index { |item, index| item.update_columns(position: index + 1) if item.position != index + 1 }
        log("priority_moved", field: "position", before: before, after: @cadence.reload.position)
      end

      def lane(id) = @cadence.lanes.reload.find { |lane| lane.id == id.to_i } || raise(ActiveRecord::RecordNotFound)

      def renumber_lanes
        @cadence.lanes.reload.reject(&:default?).each_with_index { |lane, index| lane.update!(position: index + 1) if lane.position != index + 1 }
        @cadence.default_lane.update!(position: @cadence.lanes.size)
      end
  end
end
