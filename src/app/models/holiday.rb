# Feriado estadual (sem município) ou municipal, importado pelo administrador (11, R249). Os feriados nacionais não ficam aqui: são calculados
# (`Charges::BusinessDays`). Mudar a tabela não muda vencimento já gerado.
class Holiday < ApplicationRecord
  belongs_to :municipality, optional: true

  validates :state, presence: true, format: { with: /\A[A-Z]{2}\z/ }
  validates :date, :name, presence: true
  validates :date, uniqueness: { scope: %i[state municipality_id] }

  scope :for_square, ->(municipality) { where(state: municipality.state).where(municipality_id: [ nil, municipality.id ]) }
end
