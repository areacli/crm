# Camada 14 (incremento 10): promessas de pagamento. A marca "admite promessa" nos resultados (R184), as promessas e os títulos presos a elas
# (R183 a R187), a alçada por segmento e perfil (R190), as políticas do credor e o prazo máximo do segmento (R189) e a ligação do pagamento
# à promessa (R194). Índices: cada um diz a consulta que o usa (decisão 0010); o custo na escrita está no plano técnico da camada.
class CreatePromises < ActiveRecord::Migration[8.1]
  STATES = "('pending', 'open', 'fulfilled', 'fulfilled_late', 'broken', 'canceled', 'refused', 'not_approved')".freeze

  def up
    # R184: "Prometeu pagar" nasce em cada credor que já existe, e "Negociação em andamento" passa a admitir promessa.
    add_column :contact_results, :allows_promise, :boolean, null: false, default: false
    execute "update contact_results set allows_promise = true where name_key = 'negociacao em andamento'"
    execute <<~SQL
      insert into contact_results (tenant_id, name, name_key, kind, return_rule, position, allows_promise, created_at, updated_at)
      select t.id, 'Prometeu pagar', 'prometeu pagar', 'spoke_with_customer', 'allowed',
             coalesce((select max(r.position) from contact_results r where r.tenant_id = t.id), 0) + 1, true, now(), now()
      from tenants t
      on conflict (tenant_id, name_key) do update set allows_promise = true
    SQL

    # Políticas do credor (tabela "Políticas do credor e do segmento" da 10). Cada uma tem o padrão da especificação.
    change_table :tenant_settings do |t|
      t.integer :promise_tolerance_days, null: false, default: 3
      t.string :promise_counting, limit: 20, null: false, default: "promise_only"
      t.integer :promise_min_paid_pct
      t.string :promise_after_break, limit: 20, null: false, default: "fulfilled"
      t.integer :promise_grace_days, null: false, default: 0
      t.string :promise_partial, limit: 20, null: false, default: "prevails"
      # Último número de promessa dado no credor (R187a): PRM- mais seis dígitos, dado na abertura.
      t.integer :promise_sequence, null: false, default: 0
    end
    add_check_constraint :tenant_settings, "promise_tolerance_days BETWEEN 0 AND 60 AND promise_grace_days BETWEEN 0 AND 365 AND (promise_min_paid_pct IS NULL OR promise_min_paid_pct BETWEEN 1 AND 99)",
                         name: "tenant_settings_promise_numbers"
    add_check_constraint :tenant_settings, "promise_counting IN ('promise_only', 'also_direct') AND promise_after_break IN ('fulfilled', 'stays_broken') AND promise_partial IN ('prevails', 'r46')",
                         name: "tenant_settings_promise_policies"

    # Prazo máximo da promessa, por segmento (R189).
    add_column :segments, :promise_max_days, :integer, null: false, default: 30
    add_check_constraint :segments, "promise_max_days BETWEEN 1 AND 365", name: "segments_promise_max_days"

    # Alçada: o prazo que o perfil dá sozinho em cada segmento (R190). Nasce com o segmento e com o perfil.
    create_table :promise_limits do |t|
      t.references :segment, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :profile, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.integer :max_days, null: false
      t.index %i[segment_id profile_id], unique: true
    end
    add_check_constraint :promise_limits, "max_days BETWEEN 0 AND 365", name: "promise_limits_days"
    execute <<~SQL
      insert into promise_limits (segment_id, profile_id, max_days)
      select s.id, p.id, case when p.permissions ? 'change_financial_policies' then s.promise_max_days else least(30, s.promise_max_days) end
      from segments s join profiles p on p.tenant_id = s.tenant_id
    SQL

    # Promessa (R187): feita por um cliente, sobre títulos de um só contrato, no credor dele. Os valores e as políticas ficam congelados.
    create_table :payment_promises do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :customer, null: false, foreign_key: { on_delete: :restrict }
      t.references :contract, null: false, foreign_key: { on_delete: :restrict }
      t.references :contact_attempt, null: false, foreign_key: { on_delete: :restrict }, index: { unique: true }
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.references :decided_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.references :segment, foreign_key: { on_delete: :nullify }, index: false
      t.string :number, limit: 20
      t.string :state, limit: 20, null: false
      t.string :payment_method, limit: 20, null: false
      t.date :promised_on, null: false
      t.date :contacted_on, null: false
      t.jsonb :policies, null: false, default: {}
      t.bigint :total_cents, null: false
      t.bigint :paid_cents, null: false, default: 0
      t.integer :paid_percent
      t.datetime :decided_at
      t.datetime :closed_at
      t.string :reason, limit: 300
      t.timestamps
    end
    # R194: o pagamento chega com o número da promessa; único dentro do credor (MT-10).
    add_index :payment_promises, %i[tenant_id number], unique: true, where: "number IS NOT NULL"
    # Tarefa diária e lista de pendentes: o estado e a data prometida de cada credor.
    add_index :payment_promises, %i[tenant_id state promised_on]
    # Painel: promessas feitas e encerradas nos últimos 7 e 30 dias (R205).
    add_index :payment_promises, %i[tenant_id created_at]
    add_index :payment_promises, %i[tenant_id closed_at], where: "closed_at IS NOT NULL", name: "index_payment_promises_closed_by_tenant"
    add_check_constraint :payment_promises, "state IN #{STATES}", name: "payment_promises_state"
    add_check_constraint :payment_promises, "total_cents >= 0 AND paid_cents >= 0", name: "payment_promises_amounts"

    # Títulos da promessa com o valor de cada componente na data prometida (R186, R187). `held` diz que a promessa prende o título (pendente ou
    # aberta); `removed_at` marca o título que saiu da promessa (retirado ou de outro contrato, R202, R202a), que deixa de contar no valor.
    create_table :payment_promise_bills do |t|
      t.references :promise, null: false, foreign_key: { to_table: :payment_promises, on_delete: :cascade }, index: false
      t.references :bill, null: false, foreign_key: { on_delete: :restrict }
      t.bigint :principal_cents, null: false, default: 0
      t.bigint :correction_cents, null: false, default: 0
      t.bigint :fine_cents, null: false, default: 0
      t.bigint :interest_cents, null: false, default: 0
      t.bigint :fees_cents, null: false, default: 0
      t.bigint :total_cents, null: false
      t.jsonb :paid, null: false, default: {}
      t.boolean :held, null: false, default: true
      t.datetime :removed_at
      t.string :removed_reason, limit: 20
    end
    add_index :payment_promise_bills, %i[promise_id bill_id], unique: true
    # R185: um título só está preso a uma promessa pendente ou aberta; o banco garante.
    add_index :payment_promise_bills, :bill_id, unique: true, where: "held", name: "index_payment_promise_bills_held_bill"
    add_check_constraint :payment_promise_bills, "total_cents = principal_cents + correction_cents + fine_cents + interest_cents + fees_cents", name: "payment_promise_bills_total"

    # Pagamento ligado à promessa (R194). Sem índice de propósito: a consulta vai da promessa às alocações, e o índice custaria em toda linha importada.
    add_reference :payments, :promise, foreign_key: { to_table: :payment_promises, on_delete: :restrict }, index: false
    add_column :payments, :promise_counted, :boolean, null: false, default: false
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
