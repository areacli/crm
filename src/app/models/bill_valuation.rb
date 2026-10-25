# Valor atualizado de um título vencido em cobrança, regravado a cada recálculo (09, R173). Uma linha por título; o título está no credor.
class BillValuation < ApplicationRecord
  self.primary_key = :bill_id

  belongs_to :bill
  belongs_to :tenant
end
