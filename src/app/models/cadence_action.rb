# Ação de uma célula da régua (21, R432, R433): um tipo do catálogo com o seu parâmetro. A ordem na célula é só de exibição. O parâmetro tem de
# existir e estar ativo ao salvar; desativado depois, a célula mostra o aviso e a rodada conta a ação como "parâmetro inativo" (`active_parameter?`).
# A mesma ação (tipo e parâmetro) não se repete na célula (índice único).
class CadenceAction < ApplicationRecord
  belongs_to :lane, class_name: "CadenceLane", foreign_key: :cadence_lane_id, inverse_of: :actions
  belongs_to :column, class_name: "CadenceColumn", foreign_key: :cadence_column_id, inverse_of: :actions
  belongs_to :message_piece, optional: true
  belongs_to :queue_task, optional: true

  validates :kind, inclusion: { in: Cadences::Catalog::KINDS }
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validate :same_cadence, :parameter_valid
  validate :parameter_active, if: -> { new_record? || will_save_change_to_params? || will_save_change_to_message_piece_id? || will_save_change_to_queue_task_id? || will_save_change_to_payment_method? }
  validate :unique_in_cell

  before_validation :normalize_params

  def cadence = lane&.cadence
  def removed? = removed_at.present? || lane&.removed_at.present? || column&.removed_at.present?
  def communication? = Cadences::Catalog.communication?(kind)

  # O parâmetro continua existindo e ativo (R432): peça, tarefa ou meio do credor.
  def active_parameter?
    if communication? then message_piece&.active?
    elsif kind == "task" then queue_task&.active?
    elsif kind == "issue_instrument" then Cadences::Catalog.issuable_methods(cadence.tenant).include?(payment_method)
    else true
    end
  end

  private
    def same_cadence
      errors.add(:column, :other_cadence) if lane && column && lane.cadence_id != column.cadence_id
    end

    # O que cada tipo leva (R433); o que não é do tipo é limpo antes, para a igualdade da célula não depender de chave sobrando.
    def normalize_params
      self.params = (params || {}).stringify_keys
      self.message_piece_id = nil unless communication?
      self.queue_task_id = nil unless kind == "task"
      self.payment_method = nil unless kind == "issue_instrument"
      allowed = { "issue_instrument" => %w[due_days object reissue], "proposal" => %w[form concession], "promise" => %w[value] }.fetch(kind.to_s, [])
      self.params = params.slice(*allowed)
      return unless kind == "issue_instrument"

      params["reissue"] = ActiveModel::Type::Boolean.new.cast(params["reissue"]) || false
      params["due_days"] = Integer(params["due_days"], exception: false) if params["due_days"].is_a?(String)
      params["object"] = "bill" if cadence&.bill_object?
    end

    def parameter_valid
      catalog = Cadences::Catalog
      case kind
      when *catalog::COMMUNICATIONS.keys
        errors.add(:message_piece, :blank) and return if message_piece.nil?

        errors.add(:message_piece, :other_channel) if message_piece.channel != catalog::COMMUNICATIONS.fetch(kind)
        errors.add(:message_piece, :other_tenant) if cadence && message_piece.tenant_id != cadence.tenant_id
      when "task"
        errors.add(:queue_task, :blank) and return if queue_task.nil?

        errors.add(:queue_task, :other_tenant) if cadence && queue_task.tenant_id != cadence.tenant_id
      when "issue_instrument"
        errors.add(:payment_method, :inclusion) unless catalog::RULE_METHODS.include?(payment_method.to_s)
        errors.add(:params, :due_days) unless params["due_days"].is_a?(Integer) && params["due_days"].between?(0, catalog::MAX_DUE_DAYS)
        objects = cadence&.bill_object? ? %w[bill] : catalog::ISSUE_OBJECTS
        errors.add(:params, :issue_object) unless objects.include?(params["object"])
      when "proposal"
        errors.add(:params, :proposal) unless catalog::PROPOSAL_FORMS.include?(params["form"]) && catalog::PROPOSAL_CONCESSIONS.include?(params["concession"])
      when "promise"
        errors.add(:params, :promise) unless catalog::PROMISE_VALUES.include?(params["value"])
      end
    end

    def parameter_active
      return if errors.any? || cadence.nil?

      errors.add(:base, :inactive_parameter) unless active_parameter?
    end

    def unique_in_cell
      return if lane.nil? || column.nil?

      same = CadenceAction.where(removed_at: nil, cadence_lane_id: cadence_lane_id, cadence_column_id: cadence_column_id, kind: kind, message_piece_id: message_piece_id,
                                 queue_task_id: queue_task_id, payment_method: payment_method).where("params = ?::jsonb", params.to_json)
      same = same.where.not(id: id) if persisted?
      errors.add(:base, :repeated_in_cell) if same.exists?
    end
end
