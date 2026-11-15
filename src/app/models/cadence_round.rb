# Rodada da régua (21, R435): uma por régua e hora prevista. Grava a decisão antes de pôr os comandos na fila e é retomada pela decisão gravada,
# no mesmo dia, sem repetir comando. "Atrasada" é a que rodou depois da hora, no mesmo dia (`late`); a que não rodou no dia fica "falhou".
class CadenceRound < ApplicationRecord
  include TenantScoped

  belongs_to :cadence
  # Os comandos antes das decisões: os itens apontam para a decisão.
  has_many :commands, class_name: "CadenceCommand", dependent: :destroy
  has_many :decisions, class_name: "CadenceDecision", dependent: :delete_all
  has_many :skips, class_name: "CadenceSkip", dependent: :delete_all

  enum :state, { scheduled: "scheduled", running: "running", completed: "completed", completed_with_failures: "completed_with_failures", failed: "failed" },
       validate: true

  scope :open, -> { where(state: %w[scheduled running]) }

  # O dia de Brasília da rodada: o momento de cada objeto conta até ele (R435: a retomada usa o mesmo dia).
  def day = scheduled_for.in_time_zone.to_date
  def finished? = completed? || completed_with_failures? || failed?
end
