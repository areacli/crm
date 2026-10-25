# Versão da regra efetiva de um segmento a partir de uma data (11, AN1). Só inserção.
class ChargeRuleVersion < ApplicationRecord
  belongs_to :segment
end
