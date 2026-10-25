class CreateUsersAndSessions < ActiveRecord::Migration[8.1]
  def change
    # Usuário: global, identificado pelo e-mail (MT-4). Os campos de acesso (bloqueio, senha temporária) valem a partir do incremento 2.
    create_table :users do |t|
      t.string :name, null: false
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.boolean :active, null: false, default: true
      t.timestamptz :locked_until
      t.integer :failed_attempts, null: false, default: 0, limit: 2
      t.timestamptz :last_login_at
      # Senha temporária (R37): vale até este instante; vazio depois da troca (R38).
      t.timestamptz :temporary_password_until
      t.timestamps
    end
    add_index :users, :email_address, unique: true
    add_check_constraint :users, "failed_attempts >= 0", name: "users_failed_attempts_not_negative"

    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address, limit: 45
      t.string :user_agent
      t.timestamps
    end
  end
end
