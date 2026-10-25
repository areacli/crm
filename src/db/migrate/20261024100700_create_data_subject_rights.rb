# Direitos do titular e guarda dos dados (especificação 07): cliente anonimizado e retido (R130, R138), prazo de guarda do credor (R136) e o
# registro das execuções das tarefas agendadas (O8, R137a).
class CreateDataSubjectRights < ActiveRecord::Migration[8.1]
  def change
    change_table :customers do |t|
      t.datetime :anonymized_at
      t.datetime :retained_at
      t.string :retained_reason, limit: 300
      t.references :retained_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
    end
    # Consulta: a lista de retidos da página de guarda (por credor). Índice parcial, pequeno: poucos clientes ficam retidos.
    add_index :customers, :tenant_id, name: "index_customers_retained_by_tenant", where: "retained_at IS NOT NULL"
    add_check_constraint :customers, "retained_at IS NULL OR anonymized_at IS NULL", name: "customers_anonymized_not_retained"

    add_column :tenant_settings, :retention_years, :integer, null: false, default: 5
    add_check_constraint :tenant_settings, "retention_years >= 1", name: "tenant_settings_retention_years_min"

    # Consulta: as últimas execuções de um credor, por tarefa (página de guarda).
    create_table :task_runs do |t|
      t.references :tenant, foreign_key: true, index: false
      t.string :name, limit: 60, null: false
      t.string :status, limit: 20, null: false, default: "running"
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.integer :processed, null: false, default: 0
      t.integer :failed, null: false, default: 0
      t.string :error_kind, limit: 120
      t.string :note, limit: 300
      t.index %i[tenant_id name started_at], name: "index_task_runs_on_tenant_name_started"
    end
  end
end
