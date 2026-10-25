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

ActiveRecord::Schema[8.1].define(version: 2026_10_24_100200) do
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
    t.index ["contract_id"], name: "index_bills_on_contract_id"
    t.index ["customer_id"], name: "index_bills_on_customer_id"
    t.index ["tenant_id", "customer_id", "number"], name: "index_bills_on_tenant_id_and_customer_id_and_number", unique: true
    t.index ["tenant_id", "status", "due_date"], name: "index_bills_on_tenant_id_and_status_and_due_date"
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
    t.index ["subject_type", "subject_id"], name: "index_changes_on_subject_type_and_subject_id"
    t.index ["tenant_id"], name: "index_changes_on_tenant_id"
  end

  create_table "contract_customers", primary_key: ["contract_id", "customer_id"], force: :cascade do |t|
    t.bigint "contract_id", null: false
    t.bigint "customer_id", null: false
    t.jsonb "roles", default: [], null: false
    t.index ["customer_id"], name: "index_contract_customers_on_customer_id"
  end

  create_table "contracts", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "code", limit: 100
    t.boolean "created_by_omission", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "code"], name: "index_contracts_on_tenant_id_and_code", unique: true, where: "(code IS NOT NULL)"
  end

  create_table "customers", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "document", limit: 14, null: false
    t.string "name", limit: 300, null: false
    t.string "phone", limit: 60
    t.string "email", limit: 254
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "document"], name: "index_customers_on_tenant_id_and_document", unique: true
  end

  create_table "import_rejections", force: :cascade do |t|
    t.bigint "import_id", null: false
    t.integer "line", null: false
    t.string "reason", null: false
    t.index ["import_id"], name: "index_import_rejections_on_import_id"
  end

  create_table "import_rows", id: false, force: :cascade do |t|
    t.bigint "import_id", null: false
    t.integer "line", null: false
    t.string "document", limit: 14, null: false
    t.string "number", limit: 100, null: false
    t.string "name", limit: 300
    t.string "name_key", limit: 300
    t.string "phone", limit: 60
    t.string "email", limit: 254
    t.string "contract", limit: 100
    t.string "roles", limit: 60
    t.date "due_date"
    t.bigint "amount_cents"
    t.string "description", limit: 300
    t.boolean "ok", default: true, null: false
    t.boolean "keep_document", default: false, null: false
    t.index ["import_id", "document", "number"], name: "index_import_rows_on_import_id_and_document_and_number"
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
    t.index ["tenant_id", "status"], name: "index_imports_on_tenant_id_and_status"
    t.index ["tenant_id"], name: "index_imports_one_running_per_tenant", unique: true, where: "((status)::text = ANY ((ARRAY['received'::character varying, 'checking'::character varying, 'checked'::character varying, 'confirming'::character varying])::text[]))"
    t.index ["user_id"], name: "index_imports_on_user_id"
    t.check_constraint "progress_percent >= 0 AND progress_percent <= 100", name: "imports_progress_percent_range"
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

  create_table "profiles", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "name", null: false
    t.jsonb "permissions", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "name"], name: "index_profiles_on_tenant_id_and_name", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address", limit: 45
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
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
    t.index ["tenant_id"], name: "index_tenant_settings_on_tenant_id", unique: true
  end

  create_table "tenants", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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

  add_foreign_key "access_events", "tenants", on_delete: :nullify
  add_foreign_key "access_events", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "access_events", "users", on_delete: :nullify
  add_foreign_key "bills", "contracts", on_delete: :restrict
  add_foreign_key "bills", "customers", on_delete: :restrict
  add_foreign_key "bills", "imports", column: "last_import_id", on_delete: :nullify
  add_foreign_key "bills", "imports", column: "withdrawn_import_id", on_delete: :nullify
  add_foreign_key "bills", "tenants"
  add_foreign_key "changes", "imports", on_delete: :nullify
  add_foreign_key "changes", "tenants"
  add_foreign_key "changes", "users", on_delete: :nullify
  add_foreign_key "contract_customers", "contracts", on_delete: :cascade
  add_foreign_key "contract_customers", "customers", on_delete: :cascade
  add_foreign_key "contracts", "tenants"
  add_foreign_key "customers", "tenants"
  add_foreign_key "import_rejections", "imports", on_delete: :cascade
  add_foreign_key "imports", "tenants"
  add_foreign_key "imports", "users", on_delete: :nullify
  add_foreign_key "memberships", "profiles", on_delete: :restrict
  add_foreign_key "memberships", "tenants"
  add_foreign_key "memberships", "users"
  add_foreign_key "notices", "users"
  add_foreign_key "profiles", "tenants"
  add_foreign_key "sessions", "users"
  add_foreign_key "tenant_settings", "tenants"
end
