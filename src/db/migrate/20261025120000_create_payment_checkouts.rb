# Links de checkout (12, parte C, R277): a página pública /pagar/:token, onde o cliente paga o cartão e pega o boleto e o Pix já emitidos.
# O instrumento ganha o cartão como tipo (uma cobrança de cartão por tentativa) e a ligação com o link.
class CreatePaymentCheckouts < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_checkouts do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :customer, foreign_key: true, index: { where: "customer_id IS NOT NULL" }
      # Token aleatório de 256 bits (43 caracteres URL-safe): é o próprio endereço do link. Único; a consulta da página é por ele.
      t.string :token, limit: 64, null: false
      t.string :state, limit: 20, null: false, default: "open"
      t.string :environment, limit: 10, null: false, default: "production"
      t.bigint :amount_cents, null: false
      t.string :description, limit: 200
      t.string :modalities, array: true, null: false, default: []
      t.string :highlight, limit: 10
      t.datetime :expires_at, null: false
      t.string :payer_name, limit: 300
      t.string :payer_document, limit: 14
      t.jsonb :payer_address, null: false, default: {}
      t.string :payer_email, limit: 254
      t.string :payer_phone, limit: 20
      t.string :reference_type, limit: 40
      t.bigint :reference_id
      t.integer :access_count, null: false, default: 0
      t.datetime :last_accessed_at
      t.jsonb :result, null: false, default: {}
      t.timestamps
    end
    add_check_constraint :payment_checkouts, "state IN ('open', 'card_approved', 'paid', 'card_unconfirmed', 'canceled')", name: "payment_checkouts_state"
    add_check_constraint :payment_checkouts, "amount_cents > 0", name: "payment_checkouts_amount"
    # Consulta: a página pública acha o link pelo token (todo acesso).
    add_index :payment_checkouts, :token, unique: true
    # Consulta: os links do credor (serviço e futuras telas), do mais novo ao mais antigo.
    add_index :payment_checkouts, %i[tenant_id created_at]

    add_reference :payment_instruments, :checkout, foreign_key: { to_table: :payment_checkouts }, index: { where: "checkout_id IS NOT NULL" }
    remove_check_constraint :payment_instruments, "kind IN ('boleto', 'pix')", name: "payment_instruments_kind"
    add_check_constraint :payment_instruments, "kind IN ('boleto', 'pix', 'card')", name: "payment_instruments_kind"
  end
end
