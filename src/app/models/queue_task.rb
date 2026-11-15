# Tarefa das filas (21, R446; 15, revisão 3): o que a régua põe na fila de trabalho do operador, com instrução e prazo em dias. Cadastro mínimo no
# lugar do dono; a tarefa usada numa régua não se apaga, só se desativa.
class QueueTask < ApplicationRecord
  include TenantScoped

  has_many :cadence_actions, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :tenant_id }
  validates :instruction, presence: true, length: { maximum: 500 }
  validates :due_days, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 365 }

  scope :active, -> { where(active: true) }

  def cadences = Cadence.where(id: CadenceLane.where(id: cadence_actions.select(:cadence_lane_id)).select(:cadence_id)).by_priority
end
