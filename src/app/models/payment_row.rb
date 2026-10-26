# Linha de pagamento ou estorno lida do arquivo, entre a conferência e a confirmação: armazenamento intermediário do arquivo lido, fora da auditoria
# (decisão 0021).
class PaymentRow < ApplicationRecord
  self.primary_key = %i[import_id line]

  belongs_to :import
end
