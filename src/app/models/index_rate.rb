# Índice mensal do Banco Central (R142): variação percentual de uma série num mês. É global do sistema, igual para todos os credores
# (decisão do Paulo em 23/10/2026, A3); a correção do credor fica em `IndexAdjustment`. O mês corrente é "parcial" até terminar (R143).
class IndexRate < ApplicationRecord
  # Séries e o código de cada uma no SGS do Banco Central (R142; o IGP-M é da FGV, republicado pelo Banco Central).
  CODES = { "ipca" => 433, "inpc" => 188, "igpm" => 189, "selic" => 4390 }.freeze
  SERIES = CODES.keys.freeze
  # Busca inicial (DS2): janeiro de 2000.
  FIRST_MONTH = Date.new(2000, 1, 1)

  validates :series, inclusion: { in: SERIES }
  validates :value, numericality: true

  def self.label(series) = I18n.t("indexes.series.#{series}")
end
