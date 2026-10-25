# Contas de pagamento (12, R260): o vínculo do credor com um fornecedor de boleto, Pix ou cartão, por modalidade e ambiente, ligado a um canal.
# Os campos comuns do manifesto ficam em `config`; os secretos e os arquivos (certificado .p12) ficam em `secrets`, cifrado pelo Active Record
# Encryption (texto cifrado, nunca devolvido). `file_details` guarda só titular, validade e impressão digital do certificado.
class CreatePaymentAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_accounts do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :channel, null: false, foreign_key: { to_table: :payment_channels }
      t.string :modality, limit: 10, null: false
      t.string :provider, limit: 30, null: false
      t.string :environment, limit: 12, null: false
      t.string :nickname, limit: 100, null: false
      t.boolean :active, null: false, default: true
      t.jsonb :config, null: false, default: {}
      t.text :secrets
      t.jsonb :file_details, null: false, default: {}
      t.datetime :webhook_previous_until
      t.date :certificate_warned_for
      t.datetime :last_tested_at
      t.string :last_test_status, limit: 10
      t.string :last_test_message, limit: 300
      t.timestamps
    end
    add_check_constraint :payment_accounts, "modality IN ('boleto', 'pix', 'card')", name: "payment_accounts_modality"
    add_check_constraint :payment_accounts, "environment IN ('sandbox', 'production')", name: "payment_accounts_environment"
    add_check_constraint :payment_accounts, "last_test_status IS NULL OR last_test_status IN ('ok', 'failed')", name: "payment_accounts_test_status"
    # Consulta: lista do credor por apelido; o apelido é único no credor.
    add_index :payment_accounts, %i[tenant_id nickname], unique: true
    # Consulta: a conta ativa da modalidade e do ambiente (emissão e webhook, partes B e D); garante no banco a regra R260.
    add_index :payment_accounts, %i[tenant_id modality environment], unique: true, where: "active", name: "index_payment_accounts_active_unique"
  end
end
