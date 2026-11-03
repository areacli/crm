# Estratégia do operador entre as filas dele (15, R353), escolhida por quem o inclui nas filas: em ordem (esgota uma antes da próxima), pesos
# (proporção de entregas) ou uma de cada vez (rodízio). Uma por usuário, para todos os credores dele.
class QueueStrategy < ApplicationRecord
  MODES = %w[ordered weighted round_robin].freeze

  belongs_to :user

  validates :mode, inclusion: { in: MODES }

  def self.for(user) = find_or_initialize_by(user: user)

  # Peso de uma fila (padrão 1).
  def weight_of(queue_id) = Array(entries).find { |entry| entry["queue_id"] == queue_id }&.fetch("weight", 1).to_i.clamp(1, 100)
end
