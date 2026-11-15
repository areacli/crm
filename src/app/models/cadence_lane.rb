# Raia da régua (21, R431): um segmento do sujeito da régua, em ordem; o sujeito fica na primeira raia cujo segmento o enquadra. A trilha padrão
# é a última, sem segmento, para os casos que nenhuma raia declarou. Raia sem ações é a forma de deixar um público fora.
class CadenceLane < ApplicationRecord
  belongs_to :cadence, inverse_of: :lanes
  belongs_to :segment, optional: true
  has_many :actions, -> { where(removed_at: nil).order(:position) }, class_name: "CadenceAction", dependent: :destroy, inverse_of: :lane

  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :segment, presence: true, unless: :default?
  validates :segment, absence: true, if: :default?
  validate :segment_fits

  private
    # O segmento é do credor da régua e do sujeito dela (na régua de contratos, os atributos do cliente se leem pelo pai, 13, R257).
    def segment_fits
      return if segment.nil? || cadence.nil?

      errors.add(:segment, :other_tenant) if segment.tenant_id != cadence.tenant_id
      errors.add(:segment, :other_subject) if segment.subject != cadence.subject
    end
end
