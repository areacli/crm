# Operações (especificação 14; plano técnico da camada 18): operação global, credenciamento por credor, pessoas da operação, vínculo com a
# operação, perfis disponíveis para operações, distribuições, origem dos registros, posse no pagamento, trilha e as políticas do credor.
# Sem conversão: a base da demonstração é recriada (13, revisão 2).
class Operations < ActiveRecord::Migration[8.1]
  def change
    create_table :operations do |t|
      t.string :cnpj, limit: 14, null: false, index: { unique: true }
      t.string :legal_name, limit: 200, null: false
      t.string :short_name, limit: 60, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :accreditations do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :operation, null: false, foreign_key: true
      t.string :status, limit: 20, null: false, default: "active"
      t.string :status_reason, limit: 300
      t.timestamps
      t.index %i[tenant_id operation_id], unique: true
      t.check_constraint "status IN ('active', 'suspended', 'ended')", name: "accreditations_status"
    end

    create_table :operation_members do |t|
      t.references :operation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.boolean :manager, null: false, default: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_reference :memberships, :operation, foreign_key: true, index: { where: "operation_id IS NOT NULL" }
    add_column :profiles, :available_to_operations, :boolean, null: false, default: false

    create_table :distributions do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :operation, null: false, foreign_key: true, index: false
      t.references :customer, foreign_key: true, index: false
      t.references :contract, foreign_key: true, index: false
      t.string :exposure, limit: 10, null: false
      t.date :starts_on, null: false
      t.date :ends_on
      t.datetime :ended_at
      t.string :end_reason, limit: 30
      t.string :end_note, limit: 300
      t.references :created_by, foreign_key: { to_table: :users }, index: false
      t.bigint :batch_id
      t.timestamps
      t.check_constraint "(customer_id IS NULL) <> (contract_id IS NULL)", name: "distributions_customer_or_contract"
      t.check_constraint "exposure IN ('overdue', 'all')", name: "distributions_exposure"
      t.check_constraint "ends_on IS NULL OR ends_on >= starts_on", name: "distributions_period"
      # O "está pra mim?" lê só as distribuições não encerradas de uma operação (plano técnico, medição de 31/10/2026).
      t.index %i[operation_id tenant_id contract_id], where: "ended_at IS NULL AND contract_id IS NOT NULL", name: "index_distributions_open_by_contract"
      t.index %i[operation_id tenant_id customer_id], where: "ended_at IS NULL AND customer_id IS NOT NULL", name: "index_distributions_open_by_customer"
      # Ficha e lista da equipe do credor: com quem está este contrato ou cliente.
      t.index %i[tenant_id contract_id], where: "contract_id IS NOT NULL", name: "index_distributions_by_contract"
      t.index %i[tenant_id customer_id], where: "customer_id IS NOT NULL", name: "index_distributions_by_customer"
    end

    # Origem (R315): nulo é a equipe do credor.
    %i[contact_attempts payment_promises agreements customer_contacts].each do |table|
      add_reference table, :operation, foreign_key: true, index: false
    end
    # Posse (R321): as operações para as quais o contrato estava na data do pagamento.
    add_column :payments, :possession_operation_ids, :bigint, array: true, null: false, default: []

    create_table :operation_trail_events do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :operation, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true, index: false
      t.string :kind, limit: 20, null: false
      t.references :customer, foreign_key: true, index: false
      t.string :query_text, limit: 100
      t.integer :results
      t.datetime :created_at, null: false
      t.index %i[operation_id created_at]
      t.index %i[tenant_id created_at]
      t.check_constraint "kind IN ('record_opened', 'search', 'not_found', 'export')", name: "operation_trail_events_kind"
    end

    # Políticas das operações (R319).
    change_table :tenant_settings, bulk: true do |t|
      t.boolean :operation_exclusive, null: false, default: true
      t.string :operation_default_exposure, limit: 10, null: false, default: "overdue"
      t.integer :operation_exposure_business_days, null: false, default: 3
      t.boolean :operation_sees_other_deals, null: false, default: false
      t.string :operation_other_contact_attempts, limit: 10, null: false, default: "summary"
      t.boolean :operation_manager_links, null: false, default: false
      t.check_constraint "operation_default_exposure IN ('overdue', 'all')", name: "tenant_settings_operation_exposure"
      t.check_constraint "operation_exposure_business_days BETWEEN 0 AND 30", name: "tenant_settings_operation_days"
      t.check_constraint "operation_other_contact_attempts IN ('summary', 'hidden')", name: "tenant_settings_operation_other_attempts"
    end
  end
end
