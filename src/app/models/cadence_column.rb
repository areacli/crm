# Coluna da régua (21, R430): um momento inteiro, em dias a partir do marco (negativo antes dele), comum a todas as raias. Não se edita: tira-se e
# inclui-se outra. Cada marco aceita uma faixa (R429): nos de atraso, D+1 em diante; nos de "desde", D+0 em diante.
class CadenceColumn < ApplicationRecord
  belongs_to :cadence, inverse_of: :columns
  has_many :actions, -> { where(removed_at: nil) }, class_name: "CadenceAction", dependent: :destroy, inverse_of: :column

  attr_readonly :offset_days

  validates :offset_days, numericality: { only_integer: true, less_than_or_equal_to: Cadences::Catalog::MAX_OFFSET },
                          uniqueness: { scope: :cadence_id, conditions: -> { where(removed_at: nil) } }
  validate :accepted_by_milestone

  # Como a tela escreve o momento: D−5, D+0, D+30.
  def label = offset_days.negative? ? "D−#{offset_days.abs}" : "D+#{offset_days}"

  private
    def accepted_by_milestone
      return if cadence.nil? || offset_days.nil?

      minimum = Cadences::Catalog.min_offset(cadence.milestone)
      errors.add(:offset_days, :below_milestone, minimum: minimum.negative? ? "D−#{minimum.abs}" : "D+#{minimum}") if offset_days < minimum
    end
end
