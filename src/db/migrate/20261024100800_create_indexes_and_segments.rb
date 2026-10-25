# Índices do Banco Central e segmentos (especificação 08): índices mensais globais (R142), correções do credor (R145), segmentos do credor
# com critérios (R148), o segmento vigente do contrato e o histórico dele (R153), e as duas colunas novas da configuração do credor (R151, R154).
class CreateIndexesAndSegments < ActiveRecord::Migration[8.1]
  def up
    # Consulta: os últimos meses de cada série (tela de índices) e a busca, pela restrição única (série, mês). Tabela pequena (4 séries x ~320 meses).
    create_table :index_rates do |t|
      t.string :series, limit: 10, null: false
      t.date :month, null: false
      t.decimal :value, precision: 9, scale: 4, null: false
      t.boolean :partial, null: false, default: false
      t.datetime :fetched_at, null: false
      t.index %i[series month], unique: true
    end
    add_check_constraint :index_rates, "series IN ('ipca', 'inpc', 'igpm', 'selic')", name: "index_rates_series"

    # Correção do credor sobre o índice global (R145, A3). Consulta: as correções do credor nos meses mostrados (restrição única).
    create_table :index_adjustments do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.string :series, limit: 10, null: false
      t.date :month, null: false
      t.decimal :value, precision: 9, scale: 4, null: false
      t.string :reason, limit: 300, null: false
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.datetime :adjusted_at, null: false
      t.index %i[tenant_id series month], unique: true
    end
    add_check_constraint :index_adjustments, "series IN ('ipca', 'inpc', 'igpm', 'selic')", name: "index_adjustments_series"

    # Segmentos do credor, em ordem; "Demais" (catch_all) nasce com o credor e fica sempre por último (R149). Critério vazio aceita qualquer valor.
    # Consulta: os segmentos de um credor (a restrição única por nome também serve à lista, tabela de poucas linhas por credor).
    create_table :segments do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.string :name, limit: 100, null: false
      t.string :name_key, limit: 100, null: false
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.boolean :catch_all, null: false, default: false
      t.integer :min_overdue_days
      t.integer :max_overdue_days
      t.bigint :min_balance_cents
      t.bigint :max_balance_cents
      t.integer :min_overdue_bills
      t.integer :max_overdue_bills
      t.integer :min_overdue_percent
      t.integer :max_overdue_percent
      t.integer :min_customers
      t.integer :max_customers
      t.integer :min_age_days
      t.integer :max_age_days
      t.string :person_type, limit: 10
      t.string :broke_agreement, limit: 5
      t.jsonb :products, null: false, default: []
      t.timestamps
      t.index %i[tenant_id name_key], unique: true
    end
    add_check_constraint :segments, "person_type IS NULL OR person_type IN ('person', 'company', 'mixed')", name: "segments_person_type"
    add_check_constraint :segments, "broke_agreement IS NULL OR broke_agreement IN ('yes', 'no')", name: "segments_broke_agreement"
    # Um só "Demais" por credor.
    add_index :segments, :tenant_id, unique: true, where: "catch_all", name: "index_segments_one_catch_all_per_tenant"

    # O segmento vigente do contrato (cópia do último do histórico) e a marca histórica "já quebrou acordo" (R148, preenchida pelos acordos).
    # Consulta nova: o filtro "Segmento" da lista de clientes e a conferência do impacto leem `contracts.segment_id`; índice novo, que só pesa
    # na escrita quando o segmento de um contrato muda (medido na V4).
    change_table :contracts do |t|
      t.references :segment, foreign_key: { on_delete: :nullify }
      t.boolean :broke_agreement, null: false, default: false
    end

    # Histórico por dia (PO-12): uma linha por mudança; duas mudanças no mesmo dia regravam a linha do dia (a restrição única serve ao ON CONFLICT
    # e à ficha). segment_id vazio é "sem segmento". Sem índice em segment_id: nenhuma consulta filtra por ele.
    create_table :contract_segments do |t|
      t.references :contract, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :segment, foreign_key: { on_delete: :restrict }, index: false
      t.date :since, null: false
      t.index %i[contract_id since], unique: true
    end

    change_table :tenant_settings do |t|
      t.string :segment_product_policy, limit: 20, null: false, default: "most_overdue"
      t.integer :segments_version, null: false, default: 0
    end

    # Todo credor já existente ganha o "Demais" (os novos nascem com ele, em Tenant.provision!).
    execute <<~SQL
      insert into segments (tenant_id, name, name_key, position, catch_all, created_at, updated_at)
      select id, 'Demais', 'demais', 0, true, now(), now() from tenants
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
