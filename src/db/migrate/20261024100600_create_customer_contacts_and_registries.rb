# Cadastros do credor e contatos do cliente (especificação 06): dados do credor (R106), contatos do cliente com origem e situação (R108),
# política tela × carga (R117), marca "invalida o contato" nos resultados (R123) e a preparação dos contatos da carga (R109).
class CreateCustomerContactsAndRegistries < ActiveRecord::Migration[8.1]
  def up
    change_table :tenants do |t|
      t.string :cnpj, limit: 14
      t.string :legal_name, limit: 300
      t.string :trade_name, limit: 300
      t.string :street, limit: 200
      t.string :number, limit: 20
      t.string :complement, limit: 100
      t.string :district, limit: 100
      t.string :city, limit: 100
      t.string :state, limit: 2
      t.string :zip, limit: 8
      t.string :email, limit: 254
      t.string :phone, limit: 60
      # Formas normalizadas (R125) para comparar com os contatos dos clientes (R126).
      t.string :email_key, limit: 254
      t.string :phone_key, limit: 20
    end
    # CNPJ único entre os credores (R106); credor sem cadastro não tem CNPJ.
    add_index :tenants, :cnpj, unique: true, where: "cnpj IS NOT NULL"

    # Consulta: `customer_contacts (customer_id, kind, key)` serve à ficha, à sugestão do acionamento, à carga (ON CONFLICT) e à regra "igual".
    # Sem índice por credor: a única consulta por credor (R126, quando o credor muda o próprio contato) é rara e aceita a leitura da tabela.
    create_table :customer_contacts do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :customer, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :kind, limit: 10, null: false
      t.string :key, limit: 300, null: false
      t.string :value, limit: 400, null: false
      t.string :street, limit: 200
      t.string :number, limit: 20
      t.string :complement, limit: 100
      t.string :district, limit: 100
      t.string :city, limit: 100
      t.string :state, limit: 2
      t.string :zip, limit: 8
      t.string :origin, limit: 20, null: false
      t.string :status, limit: 20, null: false, default: "valid"
      t.string :reason, limit: 300
      t.date :do_not_disturb_on
      t.boolean :kept_by_tenant, null: false, default: false
      t.datetime :seen_in_import_at
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.timestamps
    end
    add_index :customer_contacts, %i[customer_id kind key], unique: true
    add_check_constraint :customer_contacts, "kind IN ('phone', 'email', 'address')", name: "customer_contacts_kind"
    add_check_constraint :customer_contacts, "status IN ('valid', 'invalid', 'do_not_disturb')", name: "customer_contacts_status"

    add_column :customers, :name_kept, :boolean, null: false, default: false

    # Contatos da carga, na preparação (R109): uma linha por contato, no mesmo ciclo do COPY das linhas.
    create_table :import_contacts, id: false do |t|
      t.bigint :import_id, null: false
      t.integer :line, null: false
      t.string :document, limit: 14, null: false
      t.string :kind, limit: 10, null: false
      t.string :key, limit: 300, null: false
      t.string :value, limit: 400, null: false
      t.string :street, limit: 200
      t.string :number, limit: 20
      t.string :complement, limit: 100
      t.string :district, limit: 100
      t.string :city, limit: 100
      t.string :state, limit: 2
      t.string :zip, limit: 8
      t.boolean :tenant_contact, null: false, default: false
    end
    add_index :import_contacts, :import_id

    # Avisos da conferência que não recusam a linha (R111, R125, R126).
    create_table :import_warnings do |t|
      t.references :import, null: false, foreign_key: { on_delete: :cascade }
      t.integer :line, null: false
      t.string :reason, null: false
    end

    add_column :tenant_settings, :correction_policy, :string, limit: 20, null: false, default: "screen"
    add_column :contact_results, :invalidates_contact, :boolean, null: false, default: false
    add_column :changes, :origin, :string, limit: 20
    add_column :changes, :note, :string, limit: 300

    # O perfil Operador padrão recebe "editar cadastro de cliente" (12), como a especificação 06 prevê; o Gestor já tem todas.
    execute <<~SQL
      update profiles set permissions = permissions || '["edit_customer_registry"]'::jsonb
      where name = 'Operador' and not permissions @> '["edit_customer_registry"]'::jsonb
    SQL

    # Telefone e e-mail antigos do cliente viram contatos (copiados pelo código, que sabe normalizar); depois as colunas saem.
    migrate_old_contacts
    remove_column :customers, :phone
    remove_column :customers, :email
    remove_column :import_rows, :phone
    remove_column :import_rows, :email
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private
    # R112 não se aplica a um banco novo; a cópia protege o que já existir (ambientes de desenvolvimento). Contato antigo com formato
    # inválido migra como inválido, com o motivo.
    def migrate_old_contacts
      select_rows("select id, tenant_id, phone, email from customers where phone is not null or email is not null").each do |id, tenant_id, phone, email|
        { "phone" => phone, "email" => email }.each do |kind, raw|
          next if raw.blank?

          parsed = Registry::Normalizer.public_send(kind, raw)
          key = parsed.is_a?(Registry::ParsedContact) ? parsed.key : "#{kind}:#{raw.strip.downcase}"
          status = parsed.is_a?(Registry::ParsedContact) ? "valid" : "invalid"
          reason = status == "invalid" ? "formato inválido (cadastro anterior)" : nil
          execute(sanitize_sql([ <<~SQL, tenant_id, id, kind, key, raw.strip, status, reason ]))
            insert into customer_contacts (tenant_id, customer_id, kind, key, value, origin, status, reason, created_at, updated_at)
            values (?, ?, ?, ?, ?, 'load', ?, ?, now(), now()) on conflict do nothing
          SQL
        end
      end
    end

    def sanitize_sql(array) = ActiveRecord::Base.sanitize_sql_array(array)
end
