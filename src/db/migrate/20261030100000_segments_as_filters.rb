# Segmentação (especificação 13; decisão 0023; plano da camada 17). O segmento passa a ser um filtro nomeado (`segments`, nova) e as regras de
# encargos, promessa e acordo ficam nos itens do enquadramento financeiro (`tiers`, a tabela que era dos segmentos). Sem migração de dados
# (13, R270): a base é recriada; a tabela antiga só muda de nome e perde os critérios fixos, e os itens nascem dos segmentos na forma nova.
class SegmentsAsFilters < ActiveRecord::Migration[8.1]
  CRITERIA = %i[name name_key min_overdue_days max_overdue_days min_balance_cents max_balance_cents min_overdue_bills max_overdue_bills
                min_overdue_percent max_overdue_percent min_customers max_customers min_age_days max_age_days person_type broke_agreement products].freeze

  def up
    remove_check_constraint :segments, name: "segments_person_type"
    remove_check_constraint :segments, name: "segments_broke_agreement"
    remove_index :segments, name: "index_segments_on_tenant_id_and_name_key"
    remove_columns :segments, *CRITERIA
    rename_table :segments, :tiers
    %w[charge_pct charge_options agreement_params interest agreement_variables promise_max_days].each do |name|
      execute "alter table tiers rename constraint segments_#{name} to tiers_#{name}"
    end
    rename_index :tiers, "index_segments_one_catch_all_per_tenant", "index_tiers_one_catch_all_per_tenant_and_kind"

    rename_table :contract_segments, :contract_tiers
    { contract_tiers: nil, contracts: nil, charge_rule_versions: nil, promise_limits: nil, agreement_limits: nil, payment_promises: nil, agreements: nil }.each_key do |table|
      rename_column table, :segment_id, :tier_id
    end
    rename_column :tenant_settings, :segments_version, :tiers_version
    remove_column :tenant_settings, :segment_product_policy

    # O segmento: filtro nomeado do credor (R252), com o sujeito e a árvore da linguagem (0023, seção 1). Nome único no credor, sem acento e sem
    # maiúsculas. Consulta: os segmentos de um credor (a restrição única serve também à lista; dezenas de linhas por credor).
    create_table :segments do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.string :name, limit: 100, null: false
      t.string :name_key, limit: 100, null: false
      t.string :subject, limit: 10, null: false
      t.jsonb :expression, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index %i[tenant_id name_key], unique: true
    end
    add_check_constraint :segments, "subject IN ('contracts', 'customers')", name: "segments_subject"

    # O item do enquadramento (R265): de que enquadramento é, o segmento que o abre (vazio na trilha padrão, "Demais"). Um "Demais" por credor e
    # enquadramento.
    change_table :tiers do |t|
      t.string :kind, limit: 20, null: false, default: "financial"
      t.references :segment, foreign_key: { on_delete: :restrict }, index: false
    end
    remove_index :tiers, name: "index_tiers_one_catch_all_per_tenant_and_kind"
    add_index :tiers, %i[tenant_id kind], unique: true, where: "catch_all", name: "index_tiers_one_catch_all_per_tenant_and_kind"
    add_index :tiers, %i[tenant_id kind position], name: "index_tiers_on_tenant_id_and_kind_and_position"
    # Um segmento entra no enquadramento uma vez só (R266).
    add_index :tiers, %i[tenant_id kind segment_id], unique: true, where: "segment_id IS NOT NULL AND active", name: "index_tiers_one_per_segment"
    add_check_constraint :tiers, "kind IN ('financial')", name: "tiers_kind"
    # Sem validar as linhas que já existem: a base da demonstração ainda tem os segmentos antigos até ser recriada (13, R270; `crm:demo_reset` logo depois
    # de publicar). Linha nova ou alterada já é conferida.
    add_check_constraint :tiers, "catch_all = (segment_id IS NULL)", name: "tiers_segment_unless_catch_all", validate: false

    # Produto sem acento, sem maiúsculas e sem espaços repetidos, calculado na gravação (coluna gerada): o critério de produto compara assim (08,
    # R150; 13, R255). Medido na camada 17: calcular isto em cada consulta custava cerca de 9 s dos 11 s da base de 200 mil contratos.
    add_column :bills, :product_key, :virtual, type: :text, as: FOLDED, stored: true
  end

  FOLDED = "CASE WHEN product IS NULL OR btrim(product) = '' THEN NULL ELSE regexp_replace(translate(lower(btrim(product)), " \
           "'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc'), '\\s+', ' ', 'g') END"

  def down
    raise ActiveRecord::IrreversibleMigration, "sem volta: a base é recriada (13, R270)"
  end
end
