# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_24_101000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "access_events", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "tenant_id"
    t.bigint "actor_id"
    t.string "email_address"
    t.string "event", null: false
    t.string "ip_address", limit: 45
    t.jsonb "details"
    t.datetime "occurred_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["tenant_id", "occurred_at"], name: "index_access_events_on_tenant_id_and_occurred_at"
    t.index ["user_id", "occurred_at"], name: "index_access_events_on_user_id_and_occurred_at"
  end

  create_table "bill_valuations", primary_key: "bill_id", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "principal_cents", null: false
    t.bigint "corrected_principal_cents", null: false
    t.bigint "fine_cents", null: false
    t.bigint "interest_cents", null: false
    t.bigint "fees_cents", null: false
    t.bigint "total_cents", null: false
    t.date "calculated_on", null: false
    t.index ["tenant_id"], name: "index_bill_valuations_on_tenant_id"
  end

  create_table "bill_value_versions", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "bill_id", null: false
    t.bigint "import_id"
    t.bigint "user_id"
    t.bigint "amount_cents", null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["bill_id", "id"], name: "index_bill_value_versions_on_bill_id_and_id"
    t.check_constraint "amount_cents > 0", name: "bill_value_versions_amount_positive"
  end

  create_table "bills", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "contract_id", null: false
    t.bigint "customer_id", null: false
    t.string "number", limit: 100, null: false
    t.date "due_date", null: false
    t.bigint "amount_cents", null: false
    t.bigint "paid_cents", default: 0, null: false
    t.date "paid_on"
    t.string "description", limit: 300
    t.string "status", default: "active", null: false
    t.bigint "last_import_id"
    t.bigint "withdrawn_import_id"
    t.datetime "withdrawn_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "product", limit: 100
    t.index ["contract_id"], name: "index_bills_on_contract_id"
    t.index ["customer_id"], name: "index_bills_on_customer_id"
    t.index ["tenant_id", "customer_id", "number"], name: "index_bills_on_tenant_id_and_customer_id_and_number", unique: true
    t.index ["tenant_id", "status", "due_date"], name: "index_bills_on_tenant_id_and_status_and_due_date"
    t.index ["tenant_id"], name: "index_bills_with_excess_by_tenant", where: "(paid_cents > amount_cents)"
    t.check_constraint "amount_cents > 0", name: "bills_amount_positive"
    t.check_constraint "paid_cents >= 0", name: "bills_paid_not_negative"
  end

  create_table "changes", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "user_id"
    t.bigint "import_id"
    t.string "subject_type", limit: 30, null: false
    t.bigint "subject_id", null: false
    t.string "event", limit: 40, null: false
    t.string "field", limit: 60
    t.text "before"
    t.text "after"
    t.datetime "occurred_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "origin", limit: 20
    t.string "note", limit: 300
    t.index ["subject_type", "subject_id"], name: "index_changes_on_subject_type_and_subject_id"
    t.index ["tenant_id"], name: "index_changes_on_tenant_id"
  end

  create_table "charge_rule_versions", force: :cascade do |t|
    t.bigint "segment_id", null: false
    t.date "since", null: false
    t.jsonb "rule", null: false
    t.index ["segment_id", "since"], name: "index_charge_rule_versions_on_segment_id_and_since", unique: true
  end

  create_table "contact_attempts", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "customer_id", null: false
    t.bigint "contract_id"
    t.bigint "user_id"
    t.bigint "result_id", null: false
    t.string "result_kind", limit: 30, null: false
    t.string "channel", limit: 20, null: false
    t.string "contact_used", limit: 300
    t.text "text"
    t.datetime "contacted_at", null: false
    t.datetime "return_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "contacted_at"], name: "index_contact_attempts_on_customer_id_and_contacted_at"
    t.index ["result_id"], name: "index_contact_attempts_on_result_id"
    t.index ["tenant_id", "contacted_at"], name: "index_contact_attempts_on_tenant_id_and_contacted_at"
  end

  create_table "contact_results", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "name", limit: 100, null: false
    t.string "name_key", limit: 100, null: false
    t.string "kind", limit: 30, null: false
    t.string "return_rule", limit: 20, null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "invalidates_contact", default: false, null: false
    t.boolean "allows_promise", default: false, null: false
    t.index ["tenant_id", "name_key"], name: "index_contact_results_on_tenant_id_and_name_key", unique: true
    t.index ["tenant_id", "position"], name: "index_contact_results_on_tenant_id_and_position"
  end

  create_table "contract_customers", primary_key: ["contract_id", "customer_id"], force: :cascade do |t|
    t.bigint "contract_id", null: false
    t.bigint "customer_id", null: false
    t.jsonb "roles", default: [], null: false
    t.index ["customer_id"], name: "index_contract_customers_on_customer_id"
  end

  create_table "contract_segments", force: :cascade do |t|
    t.bigint "contract_id", null: false
    t.bigint "segment_id"
    t.date "since", null: false
    t.index ["contract_id", "since"], name: "index_contract_segments_on_contract_id_and_since", unique: true
  end

  create_table "contracts", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "code", limit: 100
    t.boolean "created_by_omission", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "segment_id"
    t.boolean "broke_agreement", default: false, null: false
    t.index ["segment_id"], name: "index_contracts_on_segment_id"
    t.index ["tenant_id", "code"], name: "index_contracts_on_tenant_id_and_code", unique: true, where: "(code IS NOT NULL)"
  end

  create_table "credits", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "contract_id", null: false
    t.bigint "payment_id"
    t.bigint "user_id"
    t.string "kind", limit: 20, null: false
    t.bigint "amount_cents", null: false
    t.string "reason", limit: 30, null: false
    t.string "note", limit: 300
    t.bigint "related_contract_id"
    t.datetime "occurred_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["contract_id"], name: "index_credits_on_contract_id"
    t.index ["tenant_id"], name: "index_credits_on_tenant_id"
    t.check_constraint "amount_cents <> 0", name: "credits_amount_not_zero"
  end

  create_table "customer_contacts", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "customer_id", null: false
    t.string "kind", limit: 10, null: false
    t.string "key", limit: 300, null: false
    t.string "value", limit: 400, null: false
    t.string "street", limit: 200
    t.string "number", limit: 20
    t.string "complement", limit: 100
    t.string "district", limit: 100
    t.string "city", limit: 100
    t.string "state", limit: 2
    t.string "zip", limit: 8
    t.string "origin", limit: 20, null: false
    t.string "status", limit: 20, default: "valid", null: false
    t.string "reason", limit: 300
    t.date "do_not_disturb_on"
    t.boolean "kept_by_tenant", default: false, null: false
    t.datetime "seen_in_import_at"
    t.bigint "updated_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "kind", "key"], name: "index_customer_contacts_on_customer_id_and_kind_and_key", unique: true
    t.check_constraint "kind::text = ANY (ARRAY['phone'::character varying::text, 'email'::character varying::text, 'address'::character varying::text])", name: "customer_contacts_kind"
    t.check_constraint "status::text = ANY (ARRAY['valid'::character varying::text, 'invalid'::character varying::text, 'do_not_disturb'::character varying::text])", name: "customer_contacts_status"
  end

  create_table "customers", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "document", limit: 14, null: false
    t.string "name", limit: 300, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "name_kept", default: false, null: false
    t.datetime "anonymized_at"
    t.datetime "retained_at"
    t.string "retained_reason", limit: 300
    t.bigint "retained_by_id"
    t.index ["tenant_id", "document"], name: "index_customers_on_tenant_id_and_document", unique: true
    t.index ["tenant_id"], name: "index_customers_retained_by_tenant", where: "(retained_at IS NOT NULL)"
    t.check_constraint "retained_at IS NULL OR anonymized_at IS NULL", name: "customers_anonymized_not_retained"
  end

  create_table "import_contacts", id: false, force: :cascade do |t|
    t.bigint "import_id", null: false
    t.integer "line", null: false
    t.string "document", limit: 14, null: false
    t.string "kind", limit: 10, null: false
    t.string "key", limit: 300, null: false
    t.string "value", limit: 400, null: false
    t.string "street", limit: 200
    t.string "number", limit: 20
    t.string "complement", limit: 100
    t.string "district", limit: 100
    t.string "city", limit: 100
    t.string "state", limit: 2
    t.string "zip", limit: 8
    t.boolean "tenant_contact", default: false, null: false
    t.index ["import_id"], name: "index_import_contacts_on_import_id"
  end

  create_table "import_rejections", force: :cascade do |t|
    t.bigint "import_id", null: false
    t.integer "line", null: false
    t.string "reason", null: false
    t.boolean "ignored", default: false, null: false
    t.index ["import_id"], name: "index_import_rejections_on_import_id"
  end

  create_table "import_rows", id: false, force: :cascade do |t|
    t.bigint "import_id", null: false
    t.integer "line", null: false
    t.string "document", limit: 14, null: false
    t.string "number", limit: 100, null: false
    t.string "name", limit: 300
    t.string "name_key", limit: 300
    t.string "contract", limit: 100
    t.string "roles", limit: 60
    t.date "due_date"
    t.bigint "amount_cents"
    t.string "description", limit: 300
    t.boolean "ok", default: true, null: false
    t.boolean "keep_document", default: false, null: false
    t.string "product", limit: 100
    t.bigint "penalty_cents"
    t.bigint "interest_cents"
    t.bigint "correction_cents"
    t.bigint "other_cents"
    t.index ["import_id", "document", "number"], name: "index_import_rows_on_import_id_and_document_and_number"
  end

  create_table "import_warnings", force: :cascade do |t|
    t.bigint "import_id", null: false
    t.integer "line", null: false
    t.string "reason", null: false
    t.index ["import_id"], name: "index_import_warnings_on_import_id"
  end

  create_table "imports", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "user_id"
    t.string "kind", default: "portfolio", null: false
    t.string "mode", null: false
    t.string "status", null: false
    t.string "original_name"
    t.string "stored_path"
    t.bigint "size_bytes", default: 0, null: false
    t.integer "progress_percent", default: 0, null: false
    t.string "progress_label"
    t.jsonb "summary"
    t.string "failure_reason"
    t.datetime "checked_at", precision: nil
    t.datetime "finished_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "confirmed_by_id"
    t.index ["tenant_id", "status"], name: "index_imports_on_tenant_id_and_status"
    t.index ["tenant_id"], name: "index_imports_one_running_per_tenant", unique: true, where: "((status)::text = ANY (ARRAY[('received'::character varying)::text, ('checking'::character varying)::text, ('checked'::character varying)::text, ('confirming'::character varying)::text]))"
    t.index ["user_id"], name: "index_imports_on_user_id"
    t.check_constraint "progress_percent >= 0 AND progress_percent <= 100", name: "imports_progress_percent_range"
  end

  create_table "index_adjustments", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "series", limit: 10, null: false
    t.date "month", null: false
    t.decimal "value", precision: 11, scale: 6, null: false
    t.string "reason", limit: 300, null: false
    t.bigint "user_id"
    t.datetime "adjusted_at", null: false
    t.index ["tenant_id", "series", "month"], name: "index_index_adjustments_on_tenant_id_and_series_and_month", unique: true
    t.check_constraint "series::text = ANY (ARRAY['ipca'::character varying::text, 'inpc'::character varying::text, 'igpm'::character varying::text, 'selic'::character varying::text, 'legal'::character varying::text])", name: "index_adjustments_series"
  end

  create_table "index_rates", force: :cascade do |t|
    t.string "series", limit: 10, null: false
    t.date "month", null: false
    t.decimal "value", precision: 11, scale: 6, null: false
    t.boolean "partial", default: false, null: false
    t.datetime "fetched_at", null: false
    t.index ["series", "month"], name: "index_index_rates_on_series_and_month", unique: true
    t.check_constraint "series::text = ANY (ARRAY['ipca'::character varying::text, 'inpc'::character varying::text, 'igpm'::character varying::text, 'selic'::character varying::text, 'legal'::character varying::text])", name: "index_rates_series"
  end

  create_table "memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "tenant_id", null: false
    t.bigint "profile_id", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["profile_id"], name: "index_memberships_on_profile_id"
    t.index ["tenant_id"], name: "index_memberships_on_tenant_id"
    t.index ["user_id", "tenant_id"], name: "index_memberships_on_user_id_and_tenant_id", unique: true
  end

  create_table "notices", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "kind", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "read_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_notices_unread_by_user", where: "(read_at IS NULL)"
  end

  create_table "payment_allocations", force: :cascade do |t|
    t.bigint "payment_id", null: false
    t.bigint "bill_id", null: false
    t.string "component", limit: 12, null: false
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.index ["bill_id"], name: "index_payment_allocations_on_bill_id"
    t.index ["payment_id"], name: "index_payment_allocations_on_payment_id"
    t.check_constraint "component::text = ANY (ARRAY['interest'::character varying::text, 'fine'::character varying::text, 'fees'::character varying::text, 'correction'::character varying::text, 'principal'::character varying::text])", name: "payment_allocations_component"
  end

  create_table "payment_channels", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "kind", limit: 20, null: false
    t.string "code", limit: 100, null: false
    t.string "description", limit: 200, null: false
    t.boolean "active", default: true, null: false
    t.string "webhook_adapter", limit: 30, default: "signed_json", null: false
    t.text "webhook_secret"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "code"], name: "index_payment_channels_on_tenant_id_and_code", unique: true
  end

  create_table "payment_promise_bills", force: :cascade do |t|
    t.bigint "promise_id", null: false
    t.bigint "bill_id", null: false
    t.bigint "principal_cents", default: 0, null: false
    t.bigint "correction_cents", default: 0, null: false
    t.bigint "fine_cents", default: 0, null: false
    t.bigint "interest_cents", default: 0, null: false
    t.bigint "fees_cents", default: 0, null: false
    t.bigint "total_cents", null: false
    t.jsonb "paid", default: {}, null: false
    t.boolean "held", default: true, null: false
    t.datetime "removed_at"
    t.string "removed_reason", limit: 20
    t.index ["bill_id"], name: "index_payment_promise_bills_held_bill", unique: true, where: "held"
    t.index ["bill_id"], name: "index_payment_promise_bills_on_bill_id"
    t.index ["promise_id", "bill_id"], name: "index_payment_promise_bills_on_promise_id_and_bill_id", unique: true
    t.check_constraint "total_cents = (principal_cents + correction_cents + fine_cents + interest_cents + fees_cents)", name: "payment_promise_bills_total"
  end

  create_table "payment_promises", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "customer_id", null: false
    t.bigint "contract_id", null: false
    t.bigint "contact_attempt_id", null: false
    t.bigint "user_id"
    t.bigint "decided_by_id"
    t.bigint "segment_id"
    t.string "number", limit: 20
    t.string "state", limit: 20, null: false
    t.string "payment_method", limit: 20, null: false
    t.date "promised_on", null: false
    t.date "contacted_on", null: false
    t.jsonb "policies", default: {}, null: false
    t.bigint "total_cents", null: false
    t.bigint "paid_cents", default: 0, null: false
    t.integer "paid_percent"
    t.datetime "decided_at"
    t.datetime "closed_at"
    t.string "reason", limit: 300
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["contact_attempt_id"], name: "index_payment_promises_on_contact_attempt_id", unique: true
    t.index ["contract_id"], name: "index_payment_promises_on_contract_id"
    t.index ["customer_id"], name: "index_payment_promises_on_customer_id"
    t.index ["tenant_id", "closed_at"], name: "index_payment_promises_closed_by_tenant", where: "(closed_at IS NOT NULL)"
    t.index ["tenant_id", "created_at"], name: "index_payment_promises_on_tenant_id_and_created_at"
    t.index ["tenant_id", "number"], name: "index_payment_promises_on_tenant_id_and_number", unique: true, where: "(number IS NOT NULL)"
    t.index ["tenant_id", "state", "promised_on"], name: "index_payment_promises_on_tenant_id_and_state_and_promised_on"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying, 'open'::character varying, 'fulfilled'::character varying, 'fulfilled_late'::character varying, 'broken'::character varying, 'canceled'::character varying, 'refused'::character varying, 'not_approved'::character varying]::text[])", name: "payment_promises_state"
    t.check_constraint "total_cents >= 0 AND paid_cents >= 0", name: "payment_promises_amounts"
  end

  create_table "payment_reversals", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "channel_id", null: false
    t.bigint "payment_id", null: false
    t.bigint "import_id"
    t.string "identifier", limit: 200, null: false
    t.date "reversed_on", null: false
    t.bigint "amount_cents", null: false
    t.bigint "from_credit_cents", default: 0, null: false
    t.bigint "from_bill_cents", default: 0, null: false
    t.string "reason", limit: 300
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payment_id"], name: "index_payment_reversals_on_payment_id"
    t.index ["tenant_id", "channel_id", "identifier"], name: "idx_on_tenant_id_channel_id_identifier_a11ff2a5cd", unique: true
    t.index ["tenant_id", "reversed_on"], name: "index_payment_reversals_on_tenant_id_and_reversed_on"
    t.check_constraint "amount_cents > 0 AND from_credit_cents >= 0 AND from_bill_cents >= 0", name: "payment_reversals_amounts"
  end

  create_table "payment_rows", id: false, force: :cascade do |t|
    t.bigint "import_id", null: false
    t.integer "line", null: false
    t.string "channel_code", limit: 100, null: false
    t.string "identifier", limit: 200, null: false
    t.string "document", limit: 14
    t.string "bill_number", limit: 100
    t.date "paid_on"
    t.bigint "amount_cents"
    t.string "payment_method", limit: 20
    t.string "payment_identifier", limit: 200
    t.string "reason", limit: 300
    t.boolean "ok", default: true, null: false
    t.boolean "registered", default: false, null: false
    t.index ["import_id", "channel_code", "identifier"], name: "idx_on_import_id_channel_code_identifier_ab3d619076"
    t.index ["import_id", "ok", "paid_on", "line"], name: "index_payment_rows_on_import_id_and_ok_and_paid_on_and_line"
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "channel_id", null: false
    t.bigint "import_id"
    t.string "identifier", limit: 200, null: false
    t.string "document", limit: 14, null: false
    t.string "bill_number", limit: 100, null: false
    t.bigint "bill_id"
    t.date "paid_on", null: false
    t.bigint "amount_cents", null: false
    t.string "payment_method", limit: 20, null: false
    t.string "status", limit: 20, null: false
    t.bigint "applied_cents", default: 0, null: false
    t.bigint "credit_cents", default: 0, null: false
    t.bigint "reversed_cents", default: 0, null: false
    t.bigint "credit_reversed_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "promise_id"
    t.boolean "promise_counted", default: false, null: false
    t.index ["bill_id"], name: "index_payments_on_bill_id"
    t.index ["tenant_id", "channel_id", "identifier"], name: "index_payments_on_tenant_id_and_channel_id_and_identifier", unique: true
    t.index ["tenant_id", "paid_on"], name: "index_payments_on_tenant_id_and_paid_on"
    t.index ["tenant_id"], name: "index_payments_pending_by_tenant", where: "((status)::text = 'pending'::text)"
    t.check_constraint "amount_cents > 0", name: "payments_amount_positive"
    t.check_constraint "applied_cents >= 0 AND credit_cents >= 0 AND reversed_cents >= 0 AND credit_reversed_cents >= 0", name: "payments_parts_not_negative"
  end

  create_table "profiles", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "name", null: false
    t.jsonb "permissions", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "name"], name: "index_profiles_on_tenant_id_and_name", unique: true
  end

  create_table "promise_limits", force: :cascade do |t|
    t.bigint "segment_id", null: false
    t.bigint "profile_id", null: false
    t.integer "max_days", null: false
    t.index ["profile_id"], name: "index_promise_limits_on_profile_id"
    t.index ["segment_id", "profile_id"], name: "index_promise_limits_on_segment_id_and_profile_id", unique: true
    t.check_constraint "max_days >= 0 AND max_days <= 365", name: "promise_limits_days"
  end

  create_table "reported_surcharges", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "bill_id", null: false
    t.bigint "import_id"
    t.bigint "penalty_cents", default: 0, null: false
    t.bigint "interest_cents", default: 0, null: false
    t.bigint "correction_cents", default: 0, null: false
    t.bigint "other_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_reported_surcharges_on_bill_id", unique: true
  end

  create_table "segments", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "name", limit: 100, null: false
    t.string "name_key", limit: 100, null: false
    t.integer "position", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.boolean "catch_all", default: false, null: false
    t.integer "min_overdue_days"
    t.integer "max_overdue_days"
    t.bigint "min_balance_cents"
    t.bigint "max_balance_cents"
    t.integer "min_overdue_bills"
    t.integer "max_overdue_bills"
    t.integer "min_overdue_percent"
    t.integer "max_overdue_percent"
    t.integer "min_customers"
    t.integer "max_customers"
    t.integer "min_age_days"
    t.integer "max_age_days"
    t.string "person_type", limit: 10
    t.string "broke_agreement", limit: 5
    t.jsonb "products", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "fine_pct", precision: 7, scale: 4
    t.string "interest_kind", limit: 10, default: "none", null: false
    t.decimal "interest_pct", precision: 7, scale: 4
    t.string "interest_form", limit: 10, default: "simple", null: false
    t.string "index_code", limit: 10
    t.decimal "fees_pct", precision: 7, scale: 4, default: "0.0", null: false
    t.boolean "fees_in_contract", default: false, null: false
    t.string "days_convention", limit: 10
    t.string "fine_base", limit: 10
    t.integer "promise_max_days", default: 30, null: false
    t.index ["tenant_id", "name_key"], name: "index_segments_on_tenant_id_and_name_key", unique: true
    t.index ["tenant_id"], name: "index_segments_one_catch_all_per_tenant", unique: true, where: "catch_all"
    t.check_constraint "(fine_pct IS NULL OR fine_pct >= 0::numeric AND fine_pct <= 100::numeric) AND (interest_pct IS NULL OR interest_pct >= 0::numeric AND interest_pct <= 100::numeric) AND fees_pct >= 0::numeric AND fees_pct <= 100::numeric", name: "segments_charge_pct"
    t.check_constraint "(index_code IS NULL OR (index_code::text = ANY (ARRAY['none'::character varying::text, 'ipca'::character varying::text, 'inpc'::character varying::text, 'igpm'::character varying::text]))) AND (days_convention IS NULL OR (days_convention::text = ANY (ARRAY['calendar'::character varying::text, 'thirty'::character varying::text]))) AND (fine_base IS NULL OR (fine_base::text = ANY (ARRAY['corrected'::character varying::text, 'face'::character varying::text])))", name: "segments_charge_options"
    t.check_constraint "(interest_kind::text = ANY (ARRAY['none'::character varying::text, 'fixed'::character varying::text, 'legal'::character varying::text])) AND (interest_form::text = ANY (ARRAY['simple'::character varying::text, 'compound'::character varying::text]))", name: "segments_interest"
    t.check_constraint "broke_agreement IS NULL OR (broke_agreement::text = ANY (ARRAY['yes'::character varying::text, 'no'::character varying::text]))", name: "segments_broke_agreement"
    t.check_constraint "person_type IS NULL OR (person_type::text = ANY (ARRAY['person'::character varying::text, 'company'::character varying::text, 'mixed'::character varying::text]))", name: "segments_person_type"
    t.check_constraint "promise_max_days >= 1 AND promise_max_days <= 365", name: "segments_promise_max_days"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address", limit: 45
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "task_runs", force: :cascade do |t|
    t.bigint "tenant_id"
    t.string "name", limit: 60, null: false
    t.string "status", limit: 20, default: "running", null: false
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.integer "processed", default: 0, null: false
    t.integer "failed", default: 0, null: false
    t.string "error_kind", limit: 120
    t.string "note", limit: 300
    t.index ["tenant_id", "name", "started_at"], name: "index_task_runs_on_tenant_name_started"
  end

  create_table "tenant_settings", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.jsonb "aging_brackets", null: false
    t.string "upcoming_display", default: "separate", null: false
    t.string "partial_payment_policy", limit: 20, default: "partial", null: false
    t.string "withdrawn_payment_policy", limit: 20, default: "prevails", null: false
    t.string "withdrawn_reversal_policy", limit: 20, default: "reopen", null: false
    t.string "reversal_month_policy", limit: 20, default: "reversal", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "discrepancy_policy", limit: 20, default: "follow", null: false
    t.string "correction_policy", limit: 20, default: "screen", null: false
    t.integer "retention_years", default: 5, null: false
    t.string "segment_product_policy", limit: 20, default: "most_overdue", null: false
    t.integer "segments_version", default: 0, null: false
    t.decimal "charge_fine_pct", precision: 7, scale: 4, default: "0.0", null: false
    t.decimal "charge_interest_pct", precision: 7, scale: 4, default: "0.0", null: false
    t.string "charge_index", limit: 10, default: "none", null: false
    t.string "charge_days_convention", limit: 10, default: "calendar", null: false
    t.string "charge_fine_base", limit: 10, default: "corrected", null: false
    t.string "missing_index_policy", limit: 20, default: "closed_only", null: false
    t.string "default_interest_form", limit: 10, default: "simple", null: false
    t.string "negative_index_policy", limit: 10, default: "floor", null: false
    t.string "old_legal_interest_policy", limit: 12, default: "selic", null: false
    t.string "surcharge_comparison_policy", limit: 10, default: "before", null: false
    t.integer "promise_tolerance_days", default: 3, null: false
    t.string "promise_counting", limit: 20, default: "promise_only", null: false
    t.integer "promise_min_paid_pct"
    t.string "promise_after_break", limit: 20, default: "fulfilled", null: false
    t.integer "promise_grace_days", default: 0, null: false
    t.string "promise_partial", limit: 20, default: "prevails", null: false
    t.integer "promise_sequence", default: 0, null: false
    t.index ["tenant_id"], name: "index_tenant_settings_on_tenant_id", unique: true
    t.check_constraint "(charge_days_convention::text = ANY (ARRAY['calendar'::character varying::text, 'thirty'::character varying::text])) AND (charge_fine_base::text = ANY (ARRAY['corrected'::character varying::text, 'face'::character varying::text]))", name: "tenant_settings_charge_conventions"
    t.check_constraint "(missing_index_policy::text = ANY (ARRAY['closed_only'::character varying::text, 'last_prorated'::character varying::text])) AND (default_interest_form::text = ANY (ARRAY['simple'::character varying::text, 'compound'::character varying::text])) AND (negative_index_policy::text = ANY (ARRAY['floor'::character varying::text, 'always'::character varying::text, 'ignore'::character varying::text])) AND (old_legal_interest_policy::text = ANY (ARRAY['selic'::character varying::text, 'one_percent'::character varying::text, 'none'::character varying::text])) AND (surcharge_comparison_policy::text = ANY (ARRAY['before'::character varying::text, 'after'::character varying::text]))", name: "tenant_settings_charge_policies"
    t.check_constraint "(promise_counting::text = ANY (ARRAY['promise_only'::character varying, 'also_direct'::character varying]::text[])) AND (promise_after_break::text = ANY (ARRAY['fulfilled'::character varying, 'stays_broken'::character varying]::text[])) AND (promise_partial::text = ANY (ARRAY['prevails'::character varying, 'r46'::character varying]::text[]))", name: "tenant_settings_promise_policies"
    t.check_constraint "charge_fine_pct >= 0::numeric AND charge_fine_pct <= 100::numeric AND charge_interest_pct >= 0::numeric AND charge_interest_pct <= 100::numeric", name: "tenant_settings_charge_pct"
    t.check_constraint "charge_index::text = ANY (ARRAY['none'::character varying::text, 'ipca'::character varying::text, 'inpc'::character varying::text, 'igpm'::character varying::text])", name: "tenant_settings_charge_index"
    t.check_constraint "promise_tolerance_days >= 0 AND promise_tolerance_days <= 60 AND promise_grace_days >= 0 AND promise_grace_days <= 365 AND (promise_min_paid_pct IS NULL OR promise_min_paid_pct >= 1 AND promise_min_paid_pct <= 99)", name: "tenant_settings_promise_numbers"
    t.check_constraint "retention_years >= 1", name: "tenant_settings_retention_years_min"
  end

  create_table "tenants", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "cnpj", limit: 14
    t.string "legal_name", limit: 300
    t.string "trade_name", limit: 300
    t.string "street", limit: 200
    t.string "number", limit: 20
    t.string "complement", limit: 100
    t.string "district", limit: 100
    t.string "city", limit: 100
    t.string "state", limit: 2
    t.string "zip", limit: 8
    t.string "email", limit: 254
    t.string "phone", limit: 60
    t.string "email_key", limit: 254
    t.string "phone_key", limit: 20
    t.index ["cnpj"], name: "index_tenants_on_cnpj", unique: true, where: "(cnpj IS NOT NULL)"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.boolean "active", default: true, null: false
    t.datetime "locked_until", precision: nil
    t.integer "failed_attempts", limit: 2, default: 0, null: false
    t.datetime "last_login_at", precision: nil
    t.datetime "temporary_password_until", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.check_constraint "failed_attempts >= 0", name: "users_failed_attempts_not_negative"
  end

  create_table "value_discrepancies", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "bill_id", null: false
    t.bigint "import_id"
    t.bigint "previous_cents", null: false
    t.bigint "reported_cents", null: false
    t.bigint "allocated_cents", null: false
    t.bigint "balance_before_cents", null: false
    t.bigint "balance_after_cents", null: false
    t.bigint "excess_cents", default: 0, null: false
    t.string "effect", limit: 20, null: false
    t.string "policy", limit: 20, null: false
    t.string "status", limit: 20, default: "open", null: false
    t.bigint "handled_by_id"
    t.datetime "handled_at"
    t.string "note", limit: 500
    t.string "choice", limit: 20
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_value_discrepancies_on_bill_id"
    t.index ["tenant_id", "status", "id"], name: "index_value_discrepancies_on_tenant_id_and_status_and_id"
  end

  create_table "webhook_events", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "channel_id", null: false
    t.string "event_id", limit: 200, null: false
    t.string "status", limit: 20, default: "received", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "outcome", limit: 300
    t.datetime "received_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "processed_at"
    t.index ["channel_id", "event_id"], name: "index_webhook_events_on_channel_id_and_event_id", unique: true
  end

  add_foreign_key "access_events", "tenants", on_delete: :nullify
  add_foreign_key "access_events", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "access_events", "users", on_delete: :nullify
  add_foreign_key "bill_valuations", "bills", on_delete: :cascade
  add_foreign_key "bill_valuations", "tenants"
  add_foreign_key "bill_value_versions", "bills", on_delete: :restrict
  add_foreign_key "bill_value_versions", "imports", on_delete: :nullify
  add_foreign_key "bill_value_versions", "tenants"
  add_foreign_key "bill_value_versions", "users", on_delete: :nullify
  add_foreign_key "bills", "contracts", on_delete: :restrict
  add_foreign_key "bills", "customers", on_delete: :restrict
  add_foreign_key "bills", "imports", column: "last_import_id", on_delete: :nullify
  add_foreign_key "bills", "imports", column: "withdrawn_import_id", on_delete: :nullify
  add_foreign_key "bills", "tenants"
  add_foreign_key "changes", "imports", on_delete: :nullify
  add_foreign_key "changes", "tenants"
  add_foreign_key "changes", "users", on_delete: :nullify
  add_foreign_key "charge_rule_versions", "segments", on_delete: :cascade
  add_foreign_key "contact_attempts", "contact_results", column: "result_id", on_delete: :restrict
  add_foreign_key "contact_attempts", "contracts", on_delete: :restrict
  add_foreign_key "contact_attempts", "customers", on_delete: :restrict
  add_foreign_key "contact_attempts", "tenants"
  add_foreign_key "contact_attempts", "users", on_delete: :nullify
  add_foreign_key "contact_results", "tenants"
  add_foreign_key "contract_customers", "contracts", on_delete: :cascade
  add_foreign_key "contract_customers", "customers", on_delete: :cascade
  add_foreign_key "contract_segments", "contracts", on_delete: :cascade
  add_foreign_key "contract_segments", "segments", on_delete: :restrict
  add_foreign_key "contracts", "segments", on_delete: :nullify
  add_foreign_key "contracts", "tenants"
  add_foreign_key "credits", "contracts", column: "related_contract_id", on_delete: :restrict
  add_foreign_key "credits", "contracts", on_delete: :restrict
  add_foreign_key "credits", "payments", on_delete: :restrict
  add_foreign_key "credits", "tenants"
  add_foreign_key "credits", "users", on_delete: :nullify
  add_foreign_key "customer_contacts", "customers", on_delete: :cascade
  add_foreign_key "customer_contacts", "tenants"
  add_foreign_key "customer_contacts", "users", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "customers", "tenants"
  add_foreign_key "customers", "users", column: "retained_by_id", on_delete: :nullify
  add_foreign_key "import_rejections", "imports", on_delete: :cascade
  add_foreign_key "import_warnings", "imports", on_delete: :cascade
  add_foreign_key "imports", "tenants"
  add_foreign_key "imports", "users", column: "confirmed_by_id", on_delete: :nullify
  add_foreign_key "imports", "users", on_delete: :nullify
  add_foreign_key "index_adjustments", "tenants"
  add_foreign_key "index_adjustments", "users", on_delete: :nullify
  add_foreign_key "memberships", "profiles", on_delete: :restrict
  add_foreign_key "memberships", "tenants"
  add_foreign_key "memberships", "users"
  add_foreign_key "notices", "users"
  add_foreign_key "payment_allocations", "bills", on_delete: :restrict
  add_foreign_key "payment_allocations", "payments", on_delete: :restrict
  add_foreign_key "payment_channels", "tenants"
  add_foreign_key "payment_promise_bills", "bills", on_delete: :restrict
  add_foreign_key "payment_promise_bills", "payment_promises", column: "promise_id", on_delete: :cascade
  add_foreign_key "payment_promises", "contact_attempts", on_delete: :restrict
  add_foreign_key "payment_promises", "contracts", on_delete: :restrict
  add_foreign_key "payment_promises", "customers", on_delete: :restrict
  add_foreign_key "payment_promises", "segments", on_delete: :nullify
  add_foreign_key "payment_promises", "tenants"
  add_foreign_key "payment_promises", "users", column: "decided_by_id", on_delete: :nullify
  add_foreign_key "payment_promises", "users", on_delete: :nullify
  add_foreign_key "payment_reversals", "imports", on_delete: :nullify
  add_foreign_key "payment_reversals", "payment_channels", column: "channel_id", on_delete: :restrict
  add_foreign_key "payment_reversals", "payments", on_delete: :restrict
  add_foreign_key "payment_reversals", "tenants"
  add_foreign_key "payments", "bills", on_delete: :restrict
  add_foreign_key "payments", "imports", on_delete: :nullify
  add_foreign_key "payments", "payment_channels", column: "channel_id", on_delete: :restrict
  add_foreign_key "payments", "payment_promises", column: "promise_id", on_delete: :restrict
  add_foreign_key "payments", "tenants"
  add_foreign_key "profiles", "tenants"
  add_foreign_key "promise_limits", "profiles", on_delete: :cascade
  add_foreign_key "promise_limits", "segments", on_delete: :cascade
  add_foreign_key "reported_surcharges", "bills", on_delete: :cascade
  add_foreign_key "reported_surcharges", "imports", on_delete: :nullify
  add_foreign_key "reported_surcharges", "tenants"
  add_foreign_key "segments", "tenants"
  add_foreign_key "sessions", "users"
  add_foreign_key "task_runs", "tenants"
  add_foreign_key "tenant_settings", "tenants"
  add_foreign_key "value_discrepancies", "bills", on_delete: :restrict
  add_foreign_key "value_discrepancies", "imports", on_delete: :nullify
  add_foreign_key "value_discrepancies", "tenants"
  add_foreign_key "value_discrepancies", "users", column: "handled_by_id", on_delete: :nullify
  add_foreign_key "webhook_events", "payment_channels", column: "channel_id", on_delete: :restrict
  add_foreign_key "webhook_events", "tenants"
end
