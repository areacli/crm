# Filas de trabalho (15; plano técnico da camada 19): os dois enquadramentos da fila (clientes e contratos), os grupos, a estratégia de cada
# operador, onde cada sujeito está (com a posição e quando fica disponível) e as entregas. A trava é do banco: os índices únicos parciais
# impedem duas entregas abertas para o mesmo sujeito e mais de uma por operador (R353, R354).
class WorkQueues < ActiveRecord::Migration[8.1]
  def up
    create_table :work_queues do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :subject, limit: 10, null: false
      t.integer :position, null: false, default: 0
      # A trilha padrão de cada sujeito: sem segmento, não se move nem se tira (R349).
      t.boolean :catch_all, null: false, default: false
      # Falso = item "sem fila": quem casa com ele não é entregue a ninguém (R349).
      t.boolean :delivers, null: false, default: true
      t.references :segment, foreign_key: true
      t.string :name, limit: 100, null: false
      t.string :order_by, limit: 30, null: false, default: "overdue_balance"
      t.string :order_tiebreak, limit: 30
      t.integer :lock_minutes, null: false, default: 15
      t.integer :interval_no_contact_minutes, null: false, default: 240
      t.integer :interval_third_party_minutes, null: false, default: 1_440
      t.integer :interval_customer_minutes, null: false, default: 4_320
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index %i[tenant_id subject catch_all], unique: true, where: "catch_all", name: "index_work_queues_one_catch_all"
      t.check_constraint "subject IN ('customers', 'contracts')", name: "work_queues_subject"
      t.check_constraint "catch_all OR segment_id IS NOT NULL", name: "work_queues_segment_unless_catch_all"
      t.check_constraint "lock_minutes BETWEEN 1 AND 240", name: "work_queues_lock_minutes"
      t.check_constraint "interval_no_contact_minutes >= 0 AND interval_third_party_minutes >= 0 AND interval_customer_minutes >= 0", name: "work_queues_intervals"
    end

    create_table :queue_groups do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :name, limit: 100, null: false
      t.timestamps
      t.index %i[tenant_id name], unique: true
    end
    create_table :queue_group_users, primary_key: %i[queue_group_id user_id] do |t|
      t.references :queue_group, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: true
    end
    create_table :queue_group_queues, primary_key: %i[queue_group_id work_queue_id] do |t|
      t.references :queue_group, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :work_queue, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false, default: 0
    end

    # Estratégia do operador entre as filas dele (R353): em ordem, pesos ou uma de cada vez; o cursor guarda onde parou.
    create_table :queue_strategies do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :mode, limit: 20, null: false, default: "ordered"
      # [{ "queue_id" => 7, "weight" => 3 }, ...] em ordem; filas do operador que não estão aqui vêm depois, na ordem dos grupos.
      t.jsonb :entries, null: false, default: []
      t.jsonb :cursor, null: false, default: {}
      t.timestamps
      t.check_constraint "mode IN ('ordered', 'weighted', 'round_robin')", name: "queue_strategies_mode"
    end

    create_table :queue_placements do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.string :subject, limit: 10, null: false
      t.bigint :subject_id, null: false
      # Nulo = sem fila.
      t.references :work_queue, foreign_key: { on_delete: :nullify }, index: false
      t.integer :rank, null: false, default: 0
      t.datetime :available_at
      # Lugar das instruções da régua (R359).
      t.text :instruction
      t.datetime :instruction_until
      t.timestamps
      t.index %i[subject subject_id], unique: true
      t.index %i[work_queue_id rank], where: "work_queue_id IS NOT NULL", name: "index_queue_placements_next"
      t.index :tenant_id
    end

    create_table :queue_deliveries do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :work_queue, null: false, foreign_key: true
      t.string :subject, limit: 10, null: false
      t.bigint :subject_id, null: false
      t.references :user, null: false, foreign_key: true, index: false
      t.datetime :delivered_at, null: false
      t.datetime :locked_until, null: false
      t.datetime :ended_at
      t.string :end_reason, limit: 20
      t.references :released_by, foreign_key: { to_table: :users }, index: false
      t.timestamps
      t.index %i[subject subject_id], unique: true, where: "ended_at IS NULL", name: "index_queue_deliveries_open_subject"
      t.index :user_id, unique: true, where: "ended_at IS NULL", name: "index_queue_deliveries_open_user"
      t.index :locked_until, where: "ended_at IS NULL", name: "index_queue_deliveries_open_lock"
      t.index %i[tenant_id delivered_at]
      t.check_constraint "end_reason IS NULL OR end_reason IN ('recorded', 'returned', 'expired', 'released', 'signed_out')", name: "queue_deliveries_end_reason"
    end

    add_column :tenant_settings, :queue_rules_version, :integer, null: false, default: 1
    Operations::Rls.install!(connection)
  end

  def down
    %w[queue_placements queue_deliveries].each do |table|
      execute("ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY")
      %w[team_all operation_read operation_insert operation_update operation_delete].each { |policy| execute("DROP POLICY IF EXISTS #{policy} ON #{table}") }
    end
    remove_column :tenant_settings, :queue_rules_version
    drop_table :queue_deliveries
    drop_table :queue_placements
    drop_table :queue_strategies
    drop_table :queue_group_queues
    drop_table :queue_group_users
    drop_table :queue_groups
    drop_table :work_queues
  end
end
