# "Disparou" (21, R434): a coluna gerou comando com item na fila para o objeto, uma vez por episódio. O item descartado por "mudou de raia" ou
# "régua desligada" desfaz o disparo (R438), para a coluna valer de novo na rodada seguinte.
class CadenceFiring < ApplicationRecord
  belongs_to :cadence
  belongs_to :column, class_name: "CadenceColumn", foreign_key: :cadence_column_id
  belongs_to :round, class_name: "CadenceRound", foreign_key: :cadence_round_id
end
