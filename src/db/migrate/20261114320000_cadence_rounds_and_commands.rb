# Régua, etapa 3 (21, R434 a R441; plano técnico da camada 23): a rodada, a decisão gravada antes da fila, os disparos e as colunas puladas por
# episódio, e os comandos com um item por objeto.
class CadenceRoundsAndCommands < ActiveRecord::Migration[8.1]
  ROUND_STATES = %w[scheduled running completed completed_with_failures failed].freeze
  ITEM_STATES = %w[queued executed failed no_return discarded].freeze

  def up
    # Desde quando a régua está ligada: a hora prevista de antes disso não é "rodada que não aconteceu".
    add_column :cadences, :enabled_since, :datetime

    # Rodada (R435): uma por régua e hora prevista. "Atrasada" é a marca `late` (roda no mesmo dia, depois da hora); o estado diz como terminou.
    create_table :cadence_rounds do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :cadence, null: false, foreign_key: true, index: false
      t.datetime :scheduled_for, null: false
      t.string :state, null: false, limit: 30, default: "scheduled"
      t.boolean :late, null: false, default: false
      t.string :failure, limit: 300
      t.jsonb :data_as_of, null: false, default: {}
      t.jsonb :summary, null: false, default: {}
      t.datetime :dispatched_at
      t.datetime :started_at
      t.datetime :decided_at
      t.datetime :prioritized_at
      t.datetime :built_at
      t.datetime :finished_at
      t.timestamps
    end
    add_check_constraint :cadence_rounds, "state in (#{ROUND_STATES.map { |state| "'#{state}'" }.join(', ')})", name: "cadence_rounds_state"
    add_index :cadence_rounds, %i[cadence_id scheduled_for], unique: true
    add_index :cadence_rounds, :cadence_id, unique: true, where: "state = 'running'", name: "index_cadence_rounds_one_running"
    add_index :cadence_rounds, %i[tenant_id scheduled_for]

    # A decisão gravada (R435): uma linha por objeto × ação da célula da última coluna alcançada. Dela saem os comandos, a retomada e a explicação
    # na ficha. `object_key` é o objeto na régua ("c<id>" contrato, "u<id>" cliente, "b<id>" fatura) e `episode_key` o episódio dele.
    create_table :cadence_decisions do |t|
      t.references :cadence_round, null: false, foreign_key: true, index: false
      t.references :cadence, null: false, foreign_key: true, index: false
      t.string :object_key, null: false, limit: 30
      t.string :episode_key, null: false, limit: 40
      t.bigint :contract_id
      t.bigint :customer_id
      t.bigint :bill_id
      t.references :cadence_lane, null: false, foreign_key: true, index: false
      t.references :cadence_column, null: false, foreign_key: true, index: false
      t.references :cadence_action, null: false, foreign_key: true, index: false
      t.string :kind, null: false, limit: 20
      t.string :state, null: false, limit: 20, default: "decided"
      t.references :deprioritized_by_cadence, foreign_key: { to_table: :cadences }, index: false
      t.datetime :created_at, null: false
    end
    add_check_constraint :cadence_decisions, "state in ('decided', 'deprioritized', 'inactive_parameter')", name: "cadence_decisions_state"
    add_index :cadence_decisions, %i[cadence_round_id id]
    add_index :cadence_decisions, %i[cadence_round_id cadence_action_id object_key], unique: true, name: "index_cadence_decisions_once_per_round"
    add_index :cadence_decisions, :contract_id, where: "contract_id is not null"
    add_index :cadence_decisions, :customer_id, where: "customer_id is not null"

    # "Disparou" (R434): a coluna gerou comando com item na fila, uma vez por episódio do objeto.
    create_table :cadence_firings do |t|
      t.references :cadence, null: false, foreign_key: true, index: false
      t.string :object_key, null: false, limit: 30
      t.string :episode_key, null: false, limit: 40
      t.references :cadence_column, null: false, foreign_key: true, index: false
      t.references :cadence_round, null: false, foreign_key: true, index: false
      t.datetime :created_at, null: false
    end
    add_index :cadence_firings, %i[cadence_id object_key episode_key cadence_column_id], unique: true, name: "index_cadence_firings_once"

    # Colunas puladas (R434): ficaram para trás sem disparar, registradas uma vez por episódio.
    create_table :cadence_skips do |t|
      t.references :cadence, null: false, foreign_key: true, index: false
      t.string :object_key, null: false, limit: 30
      t.string :episode_key, null: false, limit: 40
      t.references :cadence_column, null: false, foreign_key: true, index: false
      t.references :cadence_round, null: false, foreign_key: true
      t.datetime :created_at, null: false
    end
    add_index :cadence_skips, %i[cadence_id object_key episode_key cadence_column_id], unique: true, name: "index_cadence_skips_once"

    # Comando (R436, R441): o que vai à fila do executor do tipo. `group_key` agrupa as comunicações da mesma ação para o mesmo destinatário
    # ("a<ação>:r<cliente>") e separa as outras ações por decisão ("d<decisão>"); com ele, montar de novo na retomada não repete comando.
    create_table :cadence_commands do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :cadence_round, null: false, foreign_key: true, index: false
      t.references :cadence_action, null: false, foreign_key: true
      t.string :kind, null: false, limit: 20
      t.string :group_key, null: false, limit: 60
      t.bigint :recipient_customer_id
      t.string :state, null: false, limit: 20, default: "queued"
      t.datetime :enqueued_at
      t.datetime :claimed_at
      t.datetime :deadline_at
      t.timestamps
    end
    add_foreign_key :cadence_commands, :customers, column: :recipient_customer_id
    add_check_constraint :cadence_commands, "state in (#{ITEM_STATES.map { |state| "'#{state}'" }.join(', ')})", name: "cadence_commands_state"
    add_index :cadence_commands, %i[cadence_round_id group_key], unique: true
    add_index :cadence_commands, :cadence_round_id, where: "enqueued_at is null", name: "index_cadence_commands_to_enqueue"
    add_index :cadence_commands, :deadline_at, where: "state = 'queued'", name: "index_cadence_commands_waiting_return"

    # Item do comando (R439, R441): um por objeto; o retorno é por item.
    create_table :cadence_command_items do |t|
      t.references :cadence_command, null: false, foreign_key: true
      t.references :cadence_decision, null: false, foreign_key: true
      t.bigint :contract_id
      t.bigint :customer_id
      t.bigint :bill_id
      t.string :state, null: false, limit: 20, default: "queued"
      t.string :reason, limit: 300
      t.string :detail, limit: 300
      t.datetime :returned_at
      t.references :payment_instrument, foreign_key: true, index: { where: "payment_instrument_id is not null" }
      t.timestamps
    end
    add_check_constraint :cadence_command_items, "state in (#{ITEM_STATES.map { |state| "'#{state}'" }.join(', ')})", name: "cadence_command_items_state"
    add_index :cadence_command_items, %i[cadence_command_id cadence_decision_id], unique: true, name: "index_cadence_command_items_once"
    add_index :cadence_command_items, %i[contract_id created_at], where: "contract_id is not null"
    add_index :cadence_command_items, %i[customer_id created_at], where: "customer_id is not null"

    Operations::Rls.install!(connection)
  end

  def down
    drop_table :cadence_command_items
    drop_table :cadence_commands
    drop_table :cadence_skips
    drop_table :cadence_firings
    drop_table :cadence_decisions
    drop_table :cadence_rounds
    remove_column :cadences, :enabled_since
  end
end
