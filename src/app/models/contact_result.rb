# Resultado de acionamento: lista do credor, mantida por quem gerencia resultados (R66, R67). O tipo é fixo e nunca muda depois de criado;
# resultado já usado não é apagado, só desativado.
class ContactResult < ApplicationRecord
  include TenantScoped

  # Os três tipos fixos por trás da lista (R66): permitem medir contatos mesmo com nomes livres.
  KINDS = { spoke_with_customer: "spoke_with_customer", spoke_with_third_party: "spoke_with_third_party", no_contact: "no_contact" }.freeze

  has_many :attempts, class_name: "ContactAttempt", foreign_key: :result_id, inverse_of: :result, dependent: :restrict_with_error

  enum :kind, KINDS, validate: true
  # `prefix` porque `required` e `allowed` não dizem a que se referem.
  enum :return_rule, { required: "required", allowed: "allowed", not_allowed: "not_allowed" }, prefix: :return, validate: true

  before_validation { self.name = name.to_s.squish; self.name_key = FoldedText.fold(name) }

  validates :name, presence: true, length: { maximum: 100 }
  validate :name_not_taken

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  def used? = attempts.exists?

  private
    # R66: o nome é único dentro do credor, sem diferença de maiúsculas e acentos (o banco também garante, pelo índice único).
    def name_not_taken
      errors.add(:name, :taken) if name_key.present? && ContactResult.where(tenant_id: tenant_id, name_key: name_key).where.not(id: id).exists?
    end
end
