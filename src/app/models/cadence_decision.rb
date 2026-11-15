# Decisão da rodada (21, R435, R436): o objeto, a raia, a coluna e a ação, gravados antes da fila. "Despriorizado" é o que perdeu para uma régua de
# maior prioridade no mesmo horário (não vai à fila e não conta como disparado); "parâmetro inativo" é a ação cuja peça, tarefa ou meio saiu de uso.
class CadenceDecision < ApplicationRecord
  belongs_to :round, class_name: "CadenceRound", foreign_key: :cadence_round_id, inverse_of: :decisions
  belongs_to :cadence
  belongs_to :lane, class_name: "CadenceLane", foreign_key: :cadence_lane_id
  belongs_to :column, class_name: "CadenceColumn", foreign_key: :cadence_column_id
  belongs_to :action, class_name: "CadenceAction", foreign_key: :cadence_action_id
  belongs_to :deprioritized_by_cadence, class_name: "Cadence", optional: true
  belongs_to :contract, optional: true
  belongs_to :customer, optional: true
  belongs_to :bill, optional: true
  has_many :items, class_name: "CadenceCommandItem", dependent: :restrict_with_error

  enum :state, { decided: "decided", deprioritized: "deprioritized", inactive_parameter: "inactive_parameter" }, validate: true
end
