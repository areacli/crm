# Instrumentos de pagamento emitidos (12, R271): um registro por boleto ou Pix. Os arquivos (PDF e imagem do QR Code) ficam no Active Storage.
# Nasce solto: a referência ao objeto cobrado é opaca (tipo e número), sem chave estrangeira, até um escopo pedir o vínculo.
class CreatePaymentInstruments < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_instruments do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :account, null: false, foreign_key: { to_table: :payment_accounts }
      t.string :provider, limit: 30, null: false
      t.references :customer, foreign_key: true, index: { where: "customer_id IS NOT NULL" }
      t.string :kind, limit: 10, null: false
      t.string :state, limit: 10, null: false, default: "emitting"
      t.bigint :amount_cents, null: false
      t.date :due_on, null: false
      t.string :external_id, limit: 100
      t.string :custom_id, limit: 35, null: false
      t.string :payer_name, limit: 300
      t.string :payer_document, limit: 14
      t.jsonb :payer_address, null: false, default: {}
      t.string :reference_type, limit: 40
      t.bigint :reference_id
      t.string :digitable_line, limit: 60
      t.text :copy_paste
      t.string :boleto_pdf_sha256, limit: 64
      t.string :pix_qr_sha256, limit: 64
      t.string :failure_reason, limit: 300
      t.jsonb :response_summary, null: false, default: {}
      t.integer :attempts, null: false, default: 0
      t.datetime :issued_at
      t.timestamps
    end
    add_check_constraint :payment_instruments, "kind IN ('boleto', 'pix')", name: "payment_instruments_kind"
    add_check_constraint :payment_instruments, "state IN ('emitting', 'active', 'paid', 'expired', 'canceled', 'failed')", name: "payment_instruments_state"
    add_check_constraint :payment_instruments, "amount_cents > 0", name: "payment_instruments_amount"
    # Consulta: o instrumento pelo nosso identificador (idempotência da emissão, R272); único por credor.
    add_index :payment_instruments, %i[tenant_id custom_id], unique: true
    # Consulta: o instrumento pelo identificador do fornecedor na conta (aviso e conciliação, parte D); só existe depois que o fornecedor responde.
    add_index :payment_instruments, %i[account_id external_id], unique: true, where: "external_id IS NOT NULL", name: "index_payment_instruments_on_account_and_external_id"
  end
end
