class CreateTenancyAndAccess < ActiveRecord::Migration[8.1]
  def change
    # Credor (tenant). Toda tabela de domínio aponta para ele (MT-1).
    create_table :tenants do |t|
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    # Configuração do credor: faixas de atraso (R18), tratamento do a vencer (R20) e as políticas de pagamento.
    create_table :tenant_settings do |t|
      t.references :tenant, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :aging_brackets, null: false
      t.string :upcoming_display, null: false, default: "separate"
      t.string :partial_payment_policy, null: false, default: "partial", limit: 20
      t.string :withdrawn_payment_policy, null: false, default: "prevails", limit: 20
      t.string :withdrawn_reversal_policy, null: false, default: "reopen", limit: 20
      t.string :reversal_month_policy, null: false, default: "reversal", limit: 20
      t.timestamps
    end

    # Perfil: conjunto de permissões, por credor (MT-21).
    create_table :profiles do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.jsonb :permissions, null: false, default: []
      t.timestamps
    end
    add_index :profiles, %i[tenant_id name], unique: true

    # Vínculo usuário × credor × perfil (MT-2). Um usuário pode ter vários vínculos.
    create_table :memberships do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :tenant, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: { on_delete: :restrict }
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :memberships, %i[user_id tenant_id], unique: true

    # Eventos de acesso: entradas, saídas, bloqueios e ações do administrador (R29, R42).
    create_table :access_events do |t|
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.references :tenant, foreign_key: { on_delete: :nullify }, index: false
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.string :email_address
      t.string :event, null: false
      t.string :ip_address, limit: 45
      t.jsonb :details
      t.timestamptz :occurred_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :access_events, %i[user_id occurred_at]
    add_index :access_events, %i[tenant_id occurred_at]

    # Avisos dentro do sistema (A5: quem foi ligado a um credor recebe um aviso).
    create_table :notices do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :kind, null: false
      t.jsonb :data, null: false, default: {}
      t.timestamptz :read_at
      t.timestamps
    end
    add_index :notices, :user_id, where: "read_at IS NULL", name: "index_notices_unread_by_user"
  end
end
