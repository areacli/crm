# Camada 9 (incremento 5): carteira revista. Versões do valor do título, divergência de valor, acréscimos informados pelo credor, produto,
# política de divergência e quem confirmou a importação. Cada índice diz a consulta que o usa (decisão 0010); o custo na escrita foi medido na
# V4 (`crm:measure_discrepancies`).
class CreateValueVersionsAndDiscrepancies < ActiveRecord::Migration[8.1]
  def change
    # Política do credor (R94): seguir o valor novo (padrão) ou manter e registrar.
    add_column :tenant_settings, :discrepancy_policy, :string, limit: 20, null: false, default: "follow"
    # Produto do título (R101), para a segmentação das políticas.
    add_column :bills, :product, :string, limit: 100
    # Quem confirmou a importação (a versão de valor guarda quem confirmou, R88).
    add_reference :imports, :confirmed_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false

    # Versões do valor original (R88): só inserção; `bills.amount_cents` é a cópia da vigente.
    create_table :bill_value_versions do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :bill, null: false, foreign_key: { on_delete: :restrict }, index: false
      t.references :import, foreign_key: { on_delete: :nullify }, index: false
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.bigint :amount_cents, null: false
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    # Histórico do título (R100) e valor vigente: as versões de um título em ordem.
    add_index :bill_value_versions, %i[bill_id id]
    add_check_constraint :bill_value_versions, "amount_cents > 0", name: "bill_value_versions_amount_positive"

    # Acréscimos já aplicados pelo credor (R102): só para conferência, não mudam valor nem saldo. Uma linha por título, a da última carga.
    create_table :reported_surcharges do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :bill, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :import, foreign_key: { on_delete: :nullify }, index: false
      t.bigint :penalty_cents, null: false, default: 0
      t.bigint :interest_cents, null: false, default: 0
      t.bigint :correction_cents, null: false, default: 0
      t.bigint :other_cents, null: false, default: 0
      t.timestamps
    end

    # Divergência de valor (R93): o credor mudou o valor de um título que já tinha pagamento aplicado.
    create_table :value_discrepancies do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :bill, null: false, foreign_key: { on_delete: :restrict }, index: false
      t.references :import, foreign_key: { on_delete: :nullify }, index: false
      t.bigint :previous_cents, null: false
      t.bigint :reported_cents, null: false
      t.bigint :allocated_cents, null: false
      t.bigint :balance_before_cents, null: false
      t.bigint :balance_after_cents, null: false
      t.bigint :excess_cents, null: false, default: 0
      t.string :effect, null: false, limit: 20
      t.string :policy, null: false, limit: 20
      t.string :status, null: false, limit: 20, default: "open"
      t.references :handled_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.datetime :handled_at
      t.string :note, limit: 500
      t.string :choice, limit: 20
      t.timestamps
    end
    # Lista do financeiro (R99), as abertas primeiro e a contagem do menu: por credor, situação e ordem.
    add_index :value_discrepancies, %i[tenant_id status id]
    # Histórico do título (R100) e aviso da ficha: as divergências de um título.
    add_index :value_discrepancies, :bill_id
    # Excedente de título com valor reduzido (R90): o resumo e a ficha só olham os títulos em que o pago passa do valor, que são poucos.
    add_index :bills, :tenant_id, where: "paid_cents > amount_cents", name: "index_bills_with_excess_by_tenant"

    # Preparação da conferência: produto e acréscimos informados (R101, R102).
    add_column :import_rows, :product, :string, limit: 100
    add_column :import_rows, :penalty_cents, :bigint
    add_column :import_rows, :interest_cents, :bigint
    add_column :import_rows, :correction_cents, :bigint
    add_column :import_rows, :other_cents, :bigint

    reversible do |direction|
      direction.up do
        # Os títulos que já existem ganham a versão 1 com o valor atual (R88).
        execute <<~SQL
          insert into bill_value_versions (tenant_id, bill_id, amount_cents, import_id, created_at)
          select tenant_id, id, amount_cents, last_import_id, created_at from bills
        SQL
      end
    end
  end
end
