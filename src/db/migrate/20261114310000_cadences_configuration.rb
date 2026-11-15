# Régua, etapa 2 (21, R428 a R433, R446; plano técnico da camada 23): a configuração da régua (régua, raias, colunas e ações da célula) e os
# cadastros mínimos que as ações usam no lugar do dono (peças da mensageria e tarefas das filas). As rodadas e os comandos vêm na etapa 3.
class CadencesConfiguration < ActiveRecord::Migration[8.1]
  MILESTONES = %w[bill_due contract_arrears customer_arrears contract_in_collection customer_in_collection contract_start contract_creation customer_registration].freeze
  KINDS = %w[sms email whatsapp letter issue_instrument proposal promise task negativation protest lawsuit credit_suspension].freeze

  def up
    # Peças (R446): o conteúdo (texto, variáveis, prévia) vem com a mensageria; aqui, nome, canal e ativa.
    create_table :message_pieces do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.string :name, null: false, limit: 100
      t.string :channel, null: false, limit: 10
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_check_constraint :message_pieces, "channel in ('sms', 'email', 'whatsapp', 'letter')", name: "message_pieces_channel"
    add_index :message_pieces, %i[tenant_id channel name], unique: true

    # Tarefas (R446; 15, revisão 3): o que a régua põe na fila de trabalho do operador, com instrução e prazo.
    create_table :queue_tasks do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.string :name, null: false, limit: 100
      t.string :instruction, null: false, limit: 500
      t.integer :due_days, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_check_constraint :queue_tasks, "due_days between 0 and 365", name: "queue_tasks_due_days"
    add_index :queue_tasks, %i[tenant_id name], unique: true

    # A régua (R428, R437, R437a). `position` é a prioridade (1 é a maior); `subject` sai do marco e, como ele, não muda.
    create_table :cadences do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.string :name, null: false, limit: 100
      t.string :purpose, null: false, limit: 20, default: "collection"
      t.string :milestone, null: false, limit: 30
      t.string :subject, null: false, limit: 20
      t.integer :position, null: false
      t.boolean :enabled, null: false, default: false
      t.string :disabled_reason, limit: 100
      t.integer :schedule_days, array: true, null: false, default: []
      t.string :schedule_time, null: false, limit: 5
      t.boolean :skip_national_holidays, null: false, default: false
      t.date :valid_from, null: false
      t.date :valid_until
      t.jsonb :return_hours, null: false, default: {}
      t.integer :version, null: false, default: 1
      t.timestamps
    end
    add_check_constraint :cadences, "purpose = 'collection'", name: "cadences_purpose"
    add_check_constraint :cadences, "milestone in (#{MILESTONES.map { |key| "'#{key}'" }.join(', ')})", name: "cadences_milestone"
    add_check_constraint :cadences, "subject in ('contracts', 'customers')", name: "cadences_subject"
    add_check_constraint :cadences, "schedule_time ~ '^([01][0-9]|2[0-3]):(00|30)$'", name: "cadences_schedule_time"
    add_check_constraint :cadences, "valid_until is null or valid_until >= valid_from", name: "cadences_validity"
    add_index :cadences, %i[tenant_id name], unique: true
    # A prioridade muda arrastando a linha: sem unicidade no índice, a troca de duas posições não esbarra nele no meio do caminho.
    add_index :cadences, %i[tenant_id position]

    # Raias (R431): o enquadramento da régua; a trilha padrão (`default`) é a última e não tem segmento.
    create_table :cadence_lanes do |t|
      t.references :cadence, null: false, foreign_key: true, index: false
      t.references :segment, foreign_key: true
      t.integer :position, null: false
      t.boolean :default, null: false, default: false
      t.timestamps
    end
    add_check_constraint :cadence_lanes, "(segment_id is null) = \"default\"", name: "cadence_lanes_segment_unless_default"
    add_index :cadence_lanes, %i[cadence_id position]
    add_index :cadence_lanes, :cadence_id, unique: true, where: "\"default\"", name: "index_cadence_lanes_one_default"

    # Colunas (R430): um momento por coluna, sem repetição.
    create_table :cadence_columns do |t|
      t.references :cadence, null: false, foreign_key: true, index: false
      t.integer :offset_days, null: false
      t.timestamps
    end
    add_check_constraint :cadence_columns, "offset_days between -365 and 3650", name: "cadence_columns_offset"
    add_index :cadence_columns, %i[cadence_id offset_days], unique: true

    # Ações da célula (R432, R433): tipo com o parâmetro. As referências aos cadastros são chaves estrangeiras, para o "usado em" e para o cadastro
    # não apagar o que uma régua usa; o resto do parâmetro (condição, vencimento, objeto, reemitir) fica em `params`.
    create_table :cadence_actions do |t|
      t.references :cadence_lane, null: false, foreign_key: true, index: false
      t.references :cadence_column, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :kind, null: false, limit: 20
      t.jsonb :params, null: false, default: {}
      t.references :message_piece, foreign_key: true, index: { where: "message_piece_id is not null" }
      t.references :queue_task, foreign_key: true, index: { where: "queue_task_id is not null" }
      t.string :payment_method, limit: 20
      t.timestamps
    end
    add_check_constraint :cadence_actions, "kind in (#{KINDS.map { |key| "'#{key}'" }.join(', ')})", name: "cadence_actions_kind"
    add_index :cadence_actions, %i[cadence_lane_id cadence_column_id kind params message_piece_id queue_task_id payment_method], unique: true,
                                nulls_not_distinct: true, name: "index_cadence_actions_unique_in_cell"

    # O perfil Gestor padrão recebe "configurar régua" (24, R445), como os credores novos; o Operador não.
    execute(<<~SQL)
      UPDATE profiles SET permissions = permissions || '["configure_cadence"]'::jsonb
      WHERE name = 'Gestor' AND NOT permissions @> '["configure_cadence"]'::jsonb
    SQL
  end

  def down
    execute("UPDATE profiles SET permissions = permissions - 'configure_cadence'")
    drop_table :cadence_actions
    drop_table :cadence_columns
    drop_table :cadence_lanes
    drop_table :cadences
    drop_table :queue_tasks
    drop_table :message_pieces
  end
end
