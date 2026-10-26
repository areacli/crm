# Contato lido da planilha de carteira (06, R109), guardado entre a conferência e a confirmação, como `ImportRow`: armazenamento intermediário
# do arquivo lido, fora da auditoria (decisão 0021).
class ImportContact < ApplicationRecord
  belongs_to :import
end
