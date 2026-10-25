# Município do IBGE (11, R249, M12): a lista que casa o endereço do cliente com a praça dos feriados. Importada pelo administrador
# (`bin/rails crm:import_municipalities`). A chave do nome é sem acento e em minúsculas, como a busca do sistema (R7).
class Municipality < ApplicationRecord
  has_many :holidays, dependent: :delete_all

  before_validation { self.name_key = FoldedText.fold(name) }

  validates :ibge_code, presence: true, format: { with: /\A\d{7}\z/ }, uniqueness: true
  validates :name, presence: true, length: { maximum: 120 }
  validates :state, presence: true, format: { with: /\A[A-Z]{2}\z/ }
  validates :name_key, uniqueness: { scope: :state }
end
