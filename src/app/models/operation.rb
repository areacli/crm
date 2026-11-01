# Operação (14, R306): parceiro de cobrança global (uma por CNPJ), que atende N credores pelo credenciamento. Só razão social, nome curto e
# CNPJ são vistos por todos os credores que a credenciam; o que ela faz num credor é desse credor (MT-1).
class Operation < ApplicationRecord
  has_many :accreditations, dependent: :restrict_with_error
  has_many :tenants, through: :accreditations
  has_many :members, class_name: "OperationMember", dependent: :restrict_with_error
  has_many :distributions, dependent: :restrict_with_error

  normalizes :cnpj, with: ->(value) { Document.normalize(value) }
  normalizes :legal_name, :short_name, with: ->(value) { value.to_s.squish }

  validates :cnpj, presence: true, uniqueness: true
  validates :legal_name, presence: true, length: { maximum: 200 }
  validates :short_name, presence: true, length: { maximum: 60 }
  validate :cnpj_is_valid

  scope :active, -> { where(active: true) }

  def managers = members.where(manager: true, active: true)

  private
    def cnpj_is_valid
      errors.add(:cnpj, :invalid) if cnpj.present? && !(cnpj.length == 14 && Document.valid_cnpj?(cnpj))
    end
end
