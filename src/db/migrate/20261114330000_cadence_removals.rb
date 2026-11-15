# Régua, etapa 4 (21, R438, R442): raia, coluna e ação que já geraram decisão não se apagam: saem da régua (`removed_at`), para o histórico das
# rodadas e dos comandos continuar apontando para elas e para o "ainda vale?" responder "ação retirada da célula". As unicidades valem só para o
# que está na régua.
class CadenceRemovals < ActiveRecord::Migration[8.1]
  def change
    add_column :cadence_lanes, :removed_at, :datetime
    add_column :cadence_columns, :removed_at, :datetime
    add_column :cadence_actions, :removed_at, :datetime

    remove_index :cadence_lanes, :cadence_id, unique: true, where: "\"default\"", name: "index_cadence_lanes_one_default"
    add_index :cadence_lanes, :cadence_id, unique: true, where: "\"default\" and removed_at is null", name: "index_cadence_lanes_one_default"
    remove_index :cadence_columns, %i[cadence_id offset_days], unique: true
    add_index :cadence_columns, %i[cadence_id offset_days], unique: true, where: "removed_at is null"
    remove_index :cadence_actions, name: "index_cadence_actions_unique_in_cell"
    add_index :cadence_actions, %i[cadence_lane_id cadence_column_id kind params message_piece_id queue_task_id payment_method], unique: true,
                                nulls_not_distinct: true, where: "removed_at is null", name: "index_cadence_actions_unique_in_cell"
  end
end
