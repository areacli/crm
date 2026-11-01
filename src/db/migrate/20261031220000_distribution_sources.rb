# Distribuição, etapa 3 da camada 18 (14, R311, R316, R317, R342 a R348): de onde ela veio (à mão, lote ou regra), o recolhimento que leva também o
# que é da operação, os lotes e os itens do enquadramento da distribuição.
class DistributionSources < ActiveRecord::Migration[8.1]
  def change
    change_table :distributions, bulk: true do |t|
      t.string :source, limit: 10, null: false, default: "manual"
      t.bigint :rule_item_id
      t.boolean :release_retention, null: false, default: false
      t.check_constraint "source IN ('manual', 'batch', 'rule')", name: "distributions_source"
    end

    create_table :distribution_batches do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :operation, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true, index: false
      t.string :kind, limit: 10, null: false
      t.references :segment, foreign_key: true, index: false
      t.string :target, limit: 10, null: false
      t.string :exposure, limit: 10, null: false
      t.date :starts_on, null: false
      t.date :ends_on
      t.string :status, limit: 20, null: false, default: "checking"
      t.jsonb :entries, null: false, default: []
      t.jsonb :summary, null: false, default: {}
      t.datetime :checked_at
      t.datetime :confirmed_at
      t.timestamps
      t.index %i[tenant_id created_at]
      t.check_constraint "kind IN ('selection', 'segment', 'file')", name: "distribution_batches_kind"
      t.check_constraint "target IN ('customer', 'contract')", name: "distribution_batches_target"
      t.check_constraint "status IN ('checking', 'checked', 'confirmed', 'discarded', 'failed')", name: "distribution_batches_status"
    end

    create_table :distribution_rule_items do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :segment, null: false, foreign_key: true
      t.integer :position, null: false
      t.bigint :operation_ids, array: true, null: false, default: []
      t.string :exposure, limit: 10, null: false, default: "overdue"
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index %i[tenant_id segment_id], unique: true, where: "active"
      t.index %i[tenant_id position]
    end
    add_column :tenant_settings, :distribution_rules_version, :integer, null: false, default: 0
  end
end
