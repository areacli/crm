class CreatePortfolio < ActiveRecord::Migration[8.1]
  def change
    # Importação de carteira: arquivo, situação, andamento e resumo da conferência (pagamentos e estornos entram depois).
    create_table :imports do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false, default: "portfolio"
      t.string :mode, null: false
      t.string :status, null: false
      t.string :original_name
      t.string :stored_path
      t.bigint :size_bytes, null: false, default: 0
      t.integer :progress_percent, null: false, default: 0
      t.string :progress_label
      t.jsonb :summary
      t.string :failure_reason
      t.timestamptz :checked_at
      t.timestamptz :finished_at
      t.timestamps
    end
    add_index :imports, %i[tenant_id status]
    add_check_constraint :imports, "progress_percent BETWEEN 0 AND 100", name: "imports_progress_percent_range"
    # Uma importação em andamento por credor (R10): garantido pelo banco, não pela lógica da aplicação.
    add_index :imports, :tenant_id, unique: true, where: "status IN ('received', 'checking', 'checked', 'confirming')", name: "index_imports_one_running_per_tenant"

    create_table :import_rejections do |t|
      t.references :import, null: false, foreign_key: { on_delete: :cascade }
      t.integer :line, null: false
      t.string :reason, null: false
    end

    # Cliente (antes "devedor"): único por credor, pelo documento (MT-9).
    create_table :customers do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.string :document, null: false, limit: 14
      t.string :name, null: false, limit: 300
      t.string :phone, limit: 60
      t.string :email, limit: 254
      t.timestamps
    end
    add_index :customers, %i[tenant_id document], unique: true

    # Contrato: obrigatório para todo título (MT-11). Sem código quando criado por omissão (MT-14).
    create_table :contracts do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.string :code, limit: 100
      t.boolean :created_by_omission, null: false, default: false
      t.timestamps
    end
    # Código único por credor quando informado; o mesmo índice atende a busca por (credor, código).
    add_index :contracts, %i[tenant_id code], unique: true, where: "code IS NOT NULL", name: "index_contracts_on_tenant_id_and_code"

    # Clientes do contrato, com os papéis de cada um (MT-12, MT-13).
    create_table :contract_customers, primary_key: %i[contract_id customer_id] do |t|
      t.references :contract, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :customer, null: false, foreign_key: { on_delete: :cascade }
      t.jsonb :roles, null: false, default: []
    end

    # Título: pertence a um contrato; valor maior que zero (R5).
    create_table :bills do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :contract, null: false, foreign_key: { on_delete: :restrict }
      t.references :customer, null: false, foreign_key: { on_delete: :restrict }
      t.string :number, null: false, limit: 100
      t.date :due_date, null: false
      t.bigint :amount_cents, null: false
      # Quanto do título já foi pago (saldo = valor - pago, R54) e quando; a baixa chega com o incremento 3.
      t.bigint :paid_cents, null: false, default: 0
      t.date :paid_on
      t.string :description, limit: 300
      t.string :status, null: false, default: "active"
      t.references :last_import, foreign_key: { to_table: :imports, on_delete: :nullify }, index: false
      t.references :withdrawn_import, foreign_key: { to_table: :imports, on_delete: :nullify }, index: false
      t.timestamptz :withdrawn_at
      t.timestamps
    end
    add_index :bills, %i[tenant_id customer_id number], unique: true
    add_index :bills, %i[tenant_id status due_date]
    add_check_constraint :bills, "amount_cents > 0", name: "bills_amount_positive"
    add_check_constraint :bills, "paid_cents >= 0", name: "bills_paid_not_negative"

    # Histórico de alterações: só inserção (R8, R13, R14, R16, R18, R29).
    create_table :changes do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.references :import, foreign_key: { on_delete: :nullify }, index: false
      t.string :subject_type, null: false, limit: 30
      t.bigint :subject_id, null: false
      t.string :event, null: false, limit: 40
      t.string :field, limit: 60
      t.text :before
      t.text :after
      t.timestamptz :occurred_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :changes, %i[subject_type subject_id]

    # Preparação da importação (decisão 0004: gravação em lote): sem registro de escrita antecipada, porque só vive entre a
    # conferência e a confirmação ou o descarte. O Rails só cria tabela sem registro de escrita com esta chave ligada.
    adapter = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    anterior = adapter.create_unlogged_tables
    adapter.create_unlogged_tables = true
    begin
      create_table :import_rows, id: false do |t|
        t.bigint :import_id, null: false
        t.integer :line, null: false
        t.string :document, null: false, limit: 14
        t.string :number, null: false, limit: 100
        t.string :name, limit: 300
        t.string :name_key, limit: 300
        t.string :phone, limit: 60
        t.string :email, limit: 254
        t.string :contract, limit: 100
        t.string :roles, limit: 60
        t.date :due_date
        t.bigint :amount_cents
        t.string :description, limit: 300
        t.boolean :ok, null: false, default: true
        t.boolean :keep_document, null: false, default: false
      end
    ensure
      adapter.create_unlogged_tables = anterior
    end
    add_index :import_rows, %i[import_id document number]
  end
end
