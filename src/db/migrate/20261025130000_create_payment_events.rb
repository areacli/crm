# Avisos dos fornecedores e conciliação (12, parte D, R281 a R284): cada aviso recebido vira um `payment_event`, único por (conta, identificador do
# evento); o instrumento ganha o vínculo com o pagamento que ele gerou, o que foi pago e devolvido e quando foi conciliado pela última vez.
class CreatePaymentEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_events do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :account, null: false, foreign_key: { to_table: :payment_accounts }, index: false
      t.references :instrument, foreign_key: { to_table: :payment_instruments }, index: { where: "instrument_id IS NOT NULL" }
      # Chave da idempotência (R282): o `endToEndId` do Pix, o token da notificação de cobranças etc.; é o adaptador que decide.
      t.string :event_id, limit: 200, null: false
      t.string :kind, limit: 20, null: false
      t.string :external_id, limit: 100
      t.bigint :amount_cents
      t.datetime :occurred_at
      t.string :previous_status, limit: 40
      t.string :current_status, limit: 40
      # Corpo mínimo (identificadores e estados; nunca dado do pagador nem de cartão).
      t.jsonb :summary, null: false, default: {}
      t.string :state, limit: 10, null: false, default: "received"
      t.string :outcome, limit: 300
      t.integer :attempts, null: false, default: 0
      t.datetime :processed_at
      t.timestamps
    end
    add_check_constraint :payment_events, "state IN ('received', 'applied', 'ignored', 'review', 'failed')", name: "payment_events_state"
    add_check_constraint :payment_events, "kind IN ('paid', 'refunded', 'canceled', 'expired', 'check', 'other')", name: "payment_events_kind"
    # Consulta: o aviso repetido (R282); também a idempotência no banco.
    add_index :payment_events, %i[account_id event_id], unique: true, name: "index_payment_events_on_account_and_event_id"
    # Consulta: a reprocessagem do credor (recebidos há tempo demais e falhos).
    add_index :payment_events, %i[tenant_id created_at], where: "state IN ('received', 'failed')", name: "index_payment_events_pending"

    add_reference :payment_instruments, :payment, foreign_key: { on_delete: :nullify }, index: { where: "payment_id IS NOT NULL" }
    add_column :payment_instruments, :paid_at, :datetime
    add_column :payment_instruments, :paid_cents, :bigint
    add_column :payment_instruments, :refunded_cents, :bigint, null: false, default: 0
    add_column :payment_instruments, :reconciled_at, :datetime
    # Consulta: a conciliação diária percorre os ativos ainda não conferidos há N dias (R283); só os ativos entram no índice.
    add_index :payment_instruments, %i[tenant_id reconciled_at], where: "state = 'active'", name: "index_payment_instruments_to_reconcile"
  end
end
