# Estorno à espera do gestor (11, R233, AG1, AH2, AJ1): o efeito de estorno que a tabela fechada de estornos não resolve fica aqui, sem efeito, até quem tem "administrar acordos"
# decidir, com motivo: reabrir pela regra base, criar um título de estorno, lançar no crédito do contrato (negativo, se preciso) ou reverter o acordo. Enquanto espera, o título continua
# pago, o acordo não pode quitar e o crédito que o pagamento gerou fica bloqueado (AK2).
class ReversalWait < ApplicationRecord
  include TenantScoped

  REASONS = %w[in_reversion before_break credit_unattributed renegotiated_title held_by_new_agreement manual].freeze
  DECISIONS = %w[reopen reversal_title credit revert].freeze

  belongs_to :payment
  belongs_to :agreement, optional: true
  belongs_to :contract
  belongs_to :decided_by, class_name: "User", optional: true

  enum :state, { waiting: "waiting", decided: "decided" }, prefix: :state, validate: true

  scope :waiting, -> { where(state: "waiting") }
  scope :oldest_first, -> { order(:created_at, :id) }

  # Há quanto tempo o estorno espera (R233, AK5), em dias.
  def waiting_days(today = Date.current) = (today - created_at.to_date).to_i

  after_commit :announce_change, on: %i[create update]

  private
    def announce_change = Agreements::Broadcast.changed(tenant, [])
end
