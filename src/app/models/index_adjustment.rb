# Correção de um índice feita por um credor (R145, R146): ajuste do credor sobre o índice global, que vale só para o cálculo dele. Um mês que
# ainda não existe no Banco Central também entra assim. Desfazer apaga a linha; o registro de cada correção e desfazimento está em `changes`.
class IndexAdjustment < ApplicationRecord
  include TenantScoped

  belongs_to :user, optional: true

  validates :series, inclusion: { in: IndexRate::SERIES }
  validates :reason, presence: true, length: { maximum: 300 }
end
