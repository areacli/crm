# Peça da mensageria (21, R446; mensageria, revisão 5): o cadastro mínimo que a régua usa no lugar do dono, até a mensageria existir. Nome, canal e
# ativa; o conteúdo (texto, variáveis, prévia) vem com a mensageria. A peça usada numa régua não se apaga, só se desativa.
class MessagePiece < ApplicationRecord
  include TenantScoped

  CHANNELS = %w[sms email whatsapp letter].freeze

  has_many :cadence_actions, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: %i[tenant_id channel] }
  validates :channel, inclusion: { in: CHANNELS }

  scope :active, -> { where(active: true) }

  # As réguas que usam a peça, para o "usado em" do cadastro.
  def cadences = Cadence.where(id: CadenceLane.where(id: cadence_actions.select(:cadence_lane_id)).select(:cadence_id)).by_priority
end
