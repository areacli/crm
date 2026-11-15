# Coluna pulada (21, R434): ficou para trás sem disparar no episódio do objeto; registrada uma vez, na rodada que a viu.
class CadenceSkip < ApplicationRecord
  belongs_to :cadence
  belongs_to :column, class_name: "CadenceColumn", foreign_key: :cadence_column_id
  belongs_to :round, class_name: "CadenceRound", foreign_key: :cadence_round_id
end
