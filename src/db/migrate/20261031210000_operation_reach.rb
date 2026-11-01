# Alcance das operações (14, R313, R314; decisão 0024): tabelas derivadas que as políticas do RLS consultam, mantidas por
# `Operations::ReachBuilder` a cada distribuição, carga, mudança de credenciamento e na tarefa diária; e os papéis e as políticas.
class OperationReach < ActiveRecord::Migration[8.1]
  def up
    create_table :operation_contracts, primary_key: %i[operation_id contract_id] do |t|
      t.bigint :operation_id, null: false
      t.bigint :contract_id, null: false
      t.bigint :tenant_id, null: false
      # all: todas as faturas; overdue: as vencidas antes de `overdue_before`; retained: só as faturas da promessa ou do acordo da operação.
      t.string :mode, limit: 10, null: false
      t.date :overdue_before
      t.index :tenant_id
      t.check_constraint "mode IN ('all', 'overdue', 'retained')", name: "operation_contracts_mode"
    end
    create_table :operation_customers, primary_key: %i[operation_id customer_id] do |t|
      t.bigint :operation_id, null: false
      t.bigint :customer_id, null: false
      t.bigint :tenant_id, null: false
      t.index :tenant_id
    end
    create_table :operation_bills, primary_key: %i[operation_id bill_id] do |t|
      t.bigint :operation_id, null: false
      t.bigint :bill_id, null: false
      t.bigint :tenant_id, null: false
      t.index :tenant_id
    end
    Operations::Rls.install!(connection)
  end

  def down
    Operations::Rls.tables.each do |table|
      execute("ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY")
      %w[team_all operation_read operation_insert operation_update operation_delete].each { |policy| execute("DROP POLICY IF EXISTS #{policy} ON #{table}") }
    end
    drop_table :operation_bills
    drop_table :operation_customers
    drop_table :operation_contracts
  end
end
