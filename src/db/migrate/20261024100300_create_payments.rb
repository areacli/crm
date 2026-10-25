# Camada 6 (incremento 3): canais de recebimento, pagamentos, estornos, livro do crédito do contrato, preparação das importações de
# pagamentos e estornos e os eventos de webhook. Índices: cada um diz a consulta que o usa (decisão 0010).
class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    # Canal de recebimento: conta, convênio ou estabelecimento de cartão; é do credor (R45). O segredo do webhook (HMAC) é cifrado.
    create_table :payment_channels do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.string :kind, null: false, limit: 20
      t.string :code, null: false, limit: 100
      t.string :description, null: false, limit: 200
      t.boolean :active, null: false, default: true
      t.string :webhook_adapter, null: false, limit: 30, default: "signed_json"
      t.text :webhook_secret
      t.timestamps
    end
    # Unicidade do código no credor (R45) e busca do canal pelo código na conferência.
    add_index :payment_channels, %i[tenant_id code], unique: true

    # Pagamento: credor + canal + identificador únicos (R48). Pendente quando o título informado ainda não está na carteira (R52a).
    create_table :payments do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :channel, null: false, foreign_key: { to_table: :payment_channels, on_delete: :restrict }, index: false
      t.references :import, foreign_key: { on_delete: :nullify }, index: false
      t.string :identifier, null: false, limit: 200
      t.string :document, null: false, limit: 14
      t.string :bill_number, null: false, limit: 100
      t.references :bill, foreign_key: { on_delete: :restrict }
      t.date :paid_on, null: false
      t.bigint :amount_cents, null: false
      t.string :payment_method, null: false, limit: 20
      t.string :status, null: false, limit: 20
      t.bigint :applied_cents, null: false, default: 0
      t.bigint :credit_cents, null: false, default: 0
      t.bigint :reversed_cents, null: false, default: 0
      t.bigint :credit_reversed_cents, null: false, default: 0
      t.timestamps
    end
    # R48: unicidade e busca do pagamento já registrado; a mesma chave serve ao estorno que procura o pagamento pelo identificador.
    add_index :payments, %i[tenant_id channel_id identifier], unique: true
    # Resumo: recuperado por mês (R58).
    add_index :payments, %i[tenant_id paid_on]
    # Pendentes reavaliados a cada conferência (R52) e contados no resumo: índice parcial, minúsculo.
    add_index :payments, :tenant_id, where: "status = 'pending'", name: "index_payments_pending_by_tenant"
    add_check_constraint :payments, "amount_cents > 0", name: "payments_amount_positive"
    add_check_constraint :payments, "applied_cents >= 0 and credit_cents >= 0 and reversed_cents >= 0 and credit_reversed_cents >= 0",
                         name: "payments_parts_not_negative"

    # Estorno de pagamento (R60 a R64), identificado por credor + canal + identificador do estorno.
    create_table :payment_reversals do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :channel, null: false, foreign_key: { to_table: :payment_channels, on_delete: :restrict }, index: false
      t.references :payment, null: false, foreign_key: { on_delete: :restrict }
      t.references :import, foreign_key: { on_delete: :nullify }, index: false
      t.string :identifier, null: false, limit: 200
      t.date :reversed_on, null: false
      t.bigint :amount_cents, null: false
      t.bigint :from_credit_cents, null: false, default: 0
      t.bigint :from_bill_cents, null: false, default: 0
      t.string :reason, limit: 300
      t.timestamps
    end
    # R61: unicidade do estorno e "já registrado, ignorado".
    add_index :payment_reversals, %i[tenant_id channel_id identifier], unique: true
    # Resumo: estornos descontados por mês (R64).
    add_index :payment_reversals, %i[tenant_id reversed_on]
    add_check_constraint :payment_reversals, "amount_cents > 0 and from_credit_cents >= 0 and from_bill_cents >= 0", name: "payment_reversals_amounts"

    # Crédito do contrato (MT-22): livro de lançamentos só de inserção; o saldo é a soma. Nunca zero.
    create_table :credits do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :contract, null: false, foreign_key: { on_delete: :restrict }
      t.references :payment, foreign_key: { on_delete: :restrict }, index: false
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.string :kind, null: false, limit: 20
      t.bigint :amount_cents, null: false
      t.string :reason, null: false, limit: 30
      t.string :note, limit: 300
      t.references :related_contract, foreign_key: { to_table: :contracts, on_delete: :restrict }, index: false
      t.datetime :occurred_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    add_check_constraint :credits, "amount_cents <> 0", name: "credits_amount_not_zero"

    # Eventos de webhook de pagamento: um por (canal, identificador do evento), o que torna o reenvio inofensivo.
    create_table :webhook_events do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :channel, null: false, foreign_key: { to_table: :payment_channels, on_delete: :restrict }, index: false
      t.string :event_id, null: false, limit: 200
      t.string :status, null: false, limit: 20, default: "received"
      t.jsonb :payload, null: false, default: {}
      t.string :outcome, limit: 300
      t.datetime :received_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :processed_at
    end
    add_index :webhook_events, %i[channel_id event_id], unique: true

    # Linhas ignoradas por já estarem registradas (R48, R61) aparecem na lista da importação, sem contar como recusa.
    add_column :import_rejections, :ignored, :boolean, null: false, default: false

    # Preparação da importação de pagamentos e de estornos (como import_rows, sem registro de escrita).
    adapter = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    anterior = adapter.create_unlogged_tables
    adapter.create_unlogged_tables = true
    begin
      create_table :payment_rows, id: false do |t|
        t.bigint :import_id, null: false
        t.integer :line, null: false
        t.string :channel_code, null: false, limit: 100
        t.string :identifier, null: false, limit: 200
        t.string :document, limit: 14
        t.string :bill_number, limit: 100
        t.date :paid_on
        t.bigint :amount_cents
        t.string :payment_method, limit: 20
        t.string :payment_identifier, limit: 200
        t.string :reason, limit: 300
        t.boolean :ok, null: false, default: true
        t.boolean :registered, null: false, default: false
      end
    ensure
      adapter.create_unlogged_tables = anterior
    end
    add_index :payment_rows, %i[import_id ok paid_on line]
    add_index :payment_rows, %i[import_id channel_code identifier]
  end
end
