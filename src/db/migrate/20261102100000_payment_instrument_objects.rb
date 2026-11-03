# Meios de pagamento e emissão de instrumentos (16; plano técnico da camada 20, parte A): o instrumento e o link de cartão passam a ter um
# objeto (um título ou uma promessa, por chave estrangeira, exatamente um), a coluna `open` (vigente) que o índice único parcial usa para
# garantir um vigente por objeto e meio de pagamento (R378), o estado "cancelamento pendente" (R390), a origem e quem pediu, o lote de
# emissão (R384) e as duas políticas novas do credor (R389, R389a). A referência opaca da 12 (`reference_type`, `reference_id`) sai: só
# existe a demonstração, recriada.
class PaymentInstrumentObjects < ActiveRecord::Migration[8.1]
  INSTRUMENT_STATES = %w[emitting active paid expired canceled failed cancel_pending].freeze

  def up
    create_table :instrument_batches do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :segment, null: false, foreign_key: true
      t.string :object_kind, limit: 20, null: false
      t.string :payment_method, limit: 20, null: false
      t.string :due_mode, limit: 10, null: false, default: "days"
      t.date :due_on
      t.integer :due_days
      t.boolean :reissue, null: false, default: false
      t.string :status, limit: 20, null: false, default: "checking"
      t.jsonb :summary, null: false, default: {}
      t.datetime :checked_at
      t.datetime :confirmed_at
      t.references :confirmed_by, foreign_key: { to_table: :users }
      t.references :task_run, foreign_key: true
      t.timestamps
      t.index %i[tenant_id created_at]
      t.check_constraint "object_kind IN ('bills', 'agreement_bills', 'promises')", name: "instrument_batches_object_kind"
      t.check_constraint "payment_method IN ('boleto', 'pix', 'card')", name: "instrument_batches_payment_method"
      t.check_constraint "due_mode IN ('date', 'days')", name: "instrument_batches_due_mode"
      t.check_constraint "status IN ('checking', 'checked', 'confirmed', 'discarded', 'failed')", name: "instrument_batches_status"
    end

    change_table :payment_instruments, bulk: true do |t|
      t.references :bill, foreign_key: true, index: false
      t.references :promise, foreign_key: { to_table: :payment_promises }, index: false
      t.boolean :open, null: false, default: true
      t.jsonb :object_snapshot, null: false, default: {}
      t.string :origin, limit: 20
      t.references :requested_by, foreign_key: { to_table: :users }, index: false
      t.references :approved_by, foreign_key: { to_table: :users }, index: false
      t.references :instrument_batch, foreign_key: true, index: false
      t.string :cancel_reason, limit: 300
      t.references :canceled_by, foreign_key: { to_table: :users }, index: false
      t.datetime :canceled_at
      t.datetime :cancel_requested_at
      t.jsonb :reissue_request
      t.references :replaced_by, foreign_key: { to_table: :payment_instruments }, index: false
      t.change :state, :string, limit: 20, default: "emitting", null: false
    end
    change_table :payment_checkouts, bulk: true do |t|
      t.references :bill, foreign_key: true, index: false
      t.references :promise, foreign_key: { to_table: :payment_promises }, index: false
      t.boolean :open, null: false, default: true
      t.jsonb :object_snapshot, null: false, default: {}
      t.string :origin, limit: 20
      t.references :requested_by, foreign_key: { to_table: :users }, index: false
      t.string :cancel_reason, limit: 300
    end
    adopt_existing_rows
    remove_column :payment_instruments, :reference_type
    remove_column :payment_instruments, :reference_id
    remove_column :payment_checkouts, :reference_type
    remove_column :payment_checkouts, :reference_id

    remove_check_constraint :payment_instruments, name: "payment_instruments_state"
    add_check_constraint :payment_instruments, "state IN (#{INSTRUMENT_STATES.map { |state| "'#{state}'" }.join(', ')})", name: "payment_instruments_state"
    add_check_constraint :payment_instruments, "num_nonnulls(bill_id, promise_id) = 1", name: "payment_instruments_one_object"
    add_check_constraint :payment_instruments, "origin IS NULL OR origin IN ('customer_page', 'registration', 'batch', 'rule', 'reissue', 'service')", name: "payment_instruments_origin"
    # Um vigente por objeto e meio de pagamento (R378): a garantia é do banco. A tentativa de cartão fica de fora (o link é que conta, R386).
    add_index :payment_instruments, %i[bill_id kind], unique: true, where: "open AND kind IN ('boleto', 'pix')", name: "index_payment_instruments_open_per_bill"
    add_index :payment_instruments, %i[promise_id kind], unique: true, where: "open AND kind IN ('boleto', 'pix')", name: "index_payment_instruments_open_per_promise"
    add_index :payment_instruments, :bill_id, name: "index_payment_instruments_on_bill_id"
    add_index :payment_instruments, :promise_id, name: "index_payment_instruments_on_promise_id"
    add_index :payment_instruments, %i[tenant_id due_on], where: "open", name: "index_payment_instruments_open_by_due"
    add_index :payment_instruments, %i[tenant_id canceled_at], where: "state = 'canceled'", name: "index_payment_instruments_canceled"
    add_index :payment_instruments, :instrument_batch_id, where: "instrument_batch_id IS NOT NULL", name: "index_payment_instruments_on_batch"

    add_check_constraint :payment_checkouts, "num_nonnulls(bill_id, promise_id) = 1", name: "payment_checkouts_one_object"
    add_index :payment_checkouts, :bill_id, unique: true, where: "open", name: "index_payment_checkouts_open_per_bill"
    add_index :payment_checkouts, :promise_id, unique: true, where: "open", name: "index_payment_checkouts_open_per_promise"

    change_table :tenant_settings, bulk: true do |t|
      t.string :instrument_reissue_policy, limit: 20, null: false, default: "cancel_only"
      t.string :agreement_issue_all_policy, limit: 20, null: false, default: "deny"
    end

    Operations::Rls.install!(connection)
  end

  # O que já existe (só a demonstração): a referência opaca da 12 vira o objeto quando aponta para um título ou uma promessa do mesmo credor; o que
  # não aponta (acordo inteiro, número em vez de id, nada) é apagado com os avisos dele, e a recriação da demonstração emite de novo. `open`
  # segue o estado, e de dois vigentes do mesmo objeto e meio fica o mais novo.
  def adopt_existing_rows
    %w[payment_instruments payment_checkouts].each do |table|
      execute(<<~SQL)
        UPDATE #{table} t SET bill_id = b.id FROM bills b WHERE t.reference_type = 'bill' AND b.id = t.reference_id AND b.tenant_id = t.tenant_id;
        UPDATE #{table} t SET promise_id = p.id FROM payment_promises p WHERE t.reference_type = 'promise' AND p.id = t.reference_id AND p.tenant_id = t.tenant_id;
      SQL
    end
    execute(<<~SQL)
      UPDATE payment_instruments i SET bill_id = c.bill_id, promise_id = c.promise_id FROM payment_checkouts c
        WHERE i.checkout_id = c.id AND i.bill_id IS NULL AND i.promise_id IS NULL;
      DELETE FROM payment_events WHERE instrument_id IN (SELECT id FROM payment_instruments WHERE bill_id IS NULL AND promise_id IS NULL);
      DELETE FROM payment_instruments WHERE bill_id IS NULL AND promise_id IS NULL;
      UPDATE payment_instruments SET checkout_id = NULL WHERE checkout_id IN (SELECT id FROM payment_checkouts WHERE bill_id IS NULL AND promise_id IS NULL);
      DELETE FROM payment_checkouts WHERE bill_id IS NULL AND promise_id IS NULL;
      UPDATE payment_instruments SET open = state NOT IN ('paid', 'canceled', 'failed');
      UPDATE payment_checkouts SET open = state NOT IN ('paid', 'canceled');
      UPDATE payment_instruments i SET open = false WHERE open AND kind IN ('boleto', 'pix') AND EXISTS (
        SELECT 1 FROM payment_instruments n WHERE n.open AND n.kind = i.kind AND n.id > i.id
          AND (n.bill_id = i.bill_id OR n.promise_id = i.promise_id));
      UPDATE payment_checkouts c SET open = false WHERE open AND EXISTS (
        SELECT 1 FROM payment_checkouts n WHERE n.open AND n.id > c.id AND (n.bill_id = c.bill_id OR n.promise_id = c.promise_id));
    SQL
  end

  def down
    execute("ALTER TABLE instrument_batches DISABLE ROW LEVEL SECURITY")
    %w[team_all operation_read operation_insert operation_update operation_delete].each { |policy| execute("DROP POLICY IF EXISTS #{policy} ON instrument_batches") }
    remove_column :tenant_settings, :instrument_reissue_policy
    remove_column :tenant_settings, :agreement_issue_all_policy
    remove_index :payment_checkouts, name: "index_payment_checkouts_open_per_bill"
    remove_index :payment_checkouts, name: "index_payment_checkouts_open_per_promise"
    remove_check_constraint :payment_checkouts, name: "payment_checkouts_one_object"
    change_table :payment_checkouts, bulk: true do |t|
      t.remove :bill_id, :promise_id, :open, :object_snapshot, :origin, :requested_by_id, :cancel_reason
      t.string :reference_type, limit: 40
      t.bigint :reference_id
    end
    %w[open_per_bill open_per_promise on_bill_id on_promise_id open_by_due canceled on_batch].each { |name| remove_index :payment_instruments, name: "index_payment_instruments_#{name}" }
    remove_check_constraint :payment_instruments, name: "payment_instruments_origin"
    remove_check_constraint :payment_instruments, name: "payment_instruments_one_object"
    remove_check_constraint :payment_instruments, name: "payment_instruments_state"
    change_table :payment_instruments, bulk: true do |t|
      t.remove :bill_id, :promise_id, :open, :object_snapshot, :origin, :requested_by_id, :approved_by_id, :instrument_batch_id, :cancel_reason,
               :canceled_by_id, :canceled_at, :cancel_requested_at, :reissue_request, :replaced_by_id
      t.string :reference_type, limit: 40
      t.bigint :reference_id
    end
    add_check_constraint :payment_instruments, "state IN ('emitting', 'active', 'paid', 'expired', 'canceled', 'failed')", name: "payment_instruments_state"
    drop_table :instrument_batches
  end
end
