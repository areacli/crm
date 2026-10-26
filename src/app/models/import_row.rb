# Linha válida (ou só a chave de uma recusada) do arquivo de carteira, guardada entre a conferência e a confirmação. É armazenamento
# intermediário do ARQUIVO LIDO, não entidade de domínio: não é auditada e some quando a importação termina (decisão 0021).
class ImportRow < ApplicationRecord
  self.primary_key = %i[import_id line]

  belongs_to :import

  scope :accepted, -> { where(ok: true) }
end
