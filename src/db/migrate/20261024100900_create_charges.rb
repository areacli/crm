# Encargos e valor atualizado (especificação 09): a taxa legal (série 29543, 6 casas), os parâmetros de encargos do credor com o override no
# segmento (R160, R207a), as cinco políticas do credor (R165, R180 a R182), o histórico das regras (AN1), a alocação dos pagamentos por
# componente (R226) e o valor atualizado de cada título (R173). Nada disso existia: os credores já criados nascem com a regra zerada.
class CreateCharges < ActiveRecord::Migration[8.1]
  SERIES = "('ipca', 'inpc', 'igpm', 'selic', 'legal')".freeze

  def up
    # A taxa legal vem com 6 casas (Resolução CMN 5.171/2024, art. 2º, § 1º): com 4, 0,379020% viraria 0,3790%.
    change_column :index_rates, :value, :decimal, precision: 11, scale: 6
    change_column :index_adjustments, :value, :decimal, precision: 11, scale: 6
    remove_check_constraint :index_rates, name: "index_rates_series"
    add_check_constraint :index_rates, "series IN #{SERIES}", name: "index_rates_series"
    remove_check_constraint :index_adjustments, name: "index_adjustments_series"
    add_check_constraint :index_adjustments, "series IN #{SERIES}", name: "index_adjustments_series"

    # Parâmetros de encargos do credor (herdados pelos segmentos que não têm valor próprio) e as políticas (R160, R165, R180 a R182).
    change_table :tenant_settings do |t|
      t.decimal :charge_fine_pct, precision: 7, scale: 4, null: false, default: 0
      t.decimal :charge_interest_pct, precision: 7, scale: 4, null: false, default: 0
      t.string :charge_index, limit: 10, null: false, default: "none"
      t.string :charge_days_convention, limit: 10, null: false, default: "calendar"
      t.string :charge_fine_base, limit: 10, null: false, default: "corrected"
      t.string :missing_index_policy, limit: 20, null: false, default: "closed_only"
      t.string :default_interest_form, limit: 10, null: false, default: "simple"
      t.string :negative_index_policy, limit: 10, null: false, default: "floor"
      t.string :old_legal_interest_policy, limit: 12, null: false, default: "selic"
      t.string :surcharge_comparison_policy, limit: 10, null: false, default: "before"
    end
    add_check_constraint :tenant_settings, "charge_fine_pct BETWEEN 0 AND 100 AND charge_interest_pct BETWEEN 0 AND 100", name: "tenant_settings_charge_pct"
    add_check_constraint :tenant_settings, "charge_index IN ('none', 'ipca', 'inpc', 'igpm')", name: "tenant_settings_charge_index"
    add_check_constraint :tenant_settings, "charge_days_convention IN ('calendar', 'thirty') AND charge_fine_base IN ('corrected', 'face')", name: "tenant_settings_charge_conventions"
    add_check_constraint :tenant_settings, "missing_index_policy IN ('closed_only', 'last_prorated') AND default_interest_form IN ('simple', 'compound') " \
                                           "AND negative_index_policy IN ('floor', 'always', 'ignore') AND old_legal_interest_policy IN ('selic', 'one_percent', 'none') " \
                                           "AND surcharge_comparison_policy IN ('before', 'after')", name: "tenant_settings_charge_policies"

    # Regra de encargos do segmento (R160). Campo vazio herda o do credor (R207a); forma, taxa legal e honorários são só do segmento.
    change_table :segments do |t|
      t.decimal :fine_pct, precision: 7, scale: 4
      t.string :interest_kind, limit: 10, null: false, default: "none"
      t.decimal :interest_pct, precision: 7, scale: 4
      t.string :interest_form, limit: 10, null: false, default: "simple"
      t.string :index_code, limit: 10
      t.decimal :fees_pct, precision: 7, scale: 4, null: false, default: 0
      t.boolean :fees_in_contract, null: false, default: false
      t.string :days_convention, limit: 10
      t.string :fine_base, limit: 10
    end
    add_check_constraint :segments, "(fine_pct IS NULL OR fine_pct BETWEEN 0 AND 100) AND (interest_pct IS NULL OR interest_pct BETWEEN 0 AND 100) AND fees_pct BETWEEN 0 AND 100", name: "segments_charge_pct"
    add_check_constraint :segments, "interest_kind IN ('none', 'fixed', 'legal') AND interest_form IN ('simple', 'compound')", name: "segments_interest"
    add_check_constraint :segments, "(index_code IS NULL OR index_code IN ('none', 'ipca', 'inpc', 'igpm')) " \
                                    "AND (days_convention IS NULL OR days_convention IN ('calendar', 'thirty')) AND (fine_base IS NULL OR fine_base IN ('corrected', 'face'))", name: "segments_charge_options"

    # Histórico das regras efetivas de cada segmento, com a data de cada mudança (AN1): o encargo até um pagamento fica pela regra vigente nele.
    # Consulta: as versões dos segmentos do credor (por conjunto, no recálculo); a restrição única serve ao ON CONFLICT do dia.
    create_table :charge_rule_versions do |t|
      t.references :segment, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.date :since, null: false
      t.jsonb :rule, null: false
      t.index %i[segment_id since], unique: true
    end

    # Alocação de cada pagamento nos componentes do valor atualizado (R226), na ordem juros, multa, honorários, correção e principal; o estorno
    # grava linhas negativas. Consultas: o recálculo lê as alocações dos títulos do credor (junção com `payments`), o estorno lê as do pagamento.
    create_table :payment_allocations do |t|
      t.references :payment, null: false, foreign_key: { on_delete: :restrict }
      t.references :bill, null: false, foreign_key: { on_delete: :restrict }
      t.string :component, limit: 12, null: false
      t.bigint :amount_cents, null: false
      t.datetime :created_at, null: false
    end
    add_check_constraint :payment_allocations, "component IN ('interest', 'fine', 'fees', 'correction', 'principal')", name: "payment_allocations_component"

    # Valor atualizado de cada título vencido em cobrança, regravado a cada recálculo (R173). Tabela à parte para não reescrever `bills`.
    # Consulta: a lista e o painel leem por título e por credor; o recálculo apaga as linhas do credor (índice por credor).
    create_table :bill_valuations, id: false do |t|
      t.bigint :bill_id, null: false, primary_key: true
      t.references :tenant, null: false, foreign_key: true
      t.bigint :principal_cents, null: false
      t.bigint :corrected_principal_cents, null: false
      t.bigint :fine_cents, null: false
      t.bigint :interest_cents, null: false
      t.bigint :fees_cents, null: false
      t.bigint :total_cents, null: false
      t.date :calculated_on, null: false
    end
    add_foreign_key :bill_valuations, :bills, on_delete: :cascade

    # Execução do recálculo (O8) já tem a tabela `task_runs`; o tipo de execução entra pelo nome.
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
