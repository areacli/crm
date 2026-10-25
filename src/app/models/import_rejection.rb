# Linha recusada na conferência, com o número da linha no arquivo e o motivo.
class ImportRejection < ApplicationRecord
  belongs_to :import
end
