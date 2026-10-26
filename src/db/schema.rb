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

ActiveRecord::Schema[8.1].define(version: 2026_10_25_150000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "abatements", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "payment_id", null: false
    t.bigint "bill_id", null: false
    t.string "kind", limit: 10, null: false
    t.string "component", limit: 40, null: false
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.index ["payment_id"], name: "index_abatements_on_payment_id"
    t.index ["tenant_id", "created_at"], name: "index_abatements_on_tenant_id_and_created_at"
    t.check_constraint "(kind::text = ANY (ARRAY['creditor'::character varying::text, 'tolerance'::character varying::text, 'minimum'::character varying::text, 'early'::character varying::text])) AND (component::text = ANY (ARRAY['interest'::character varying::text, 'fine'::character varying::text, 'fees'::character varying::text, 'correction'::character varying::text, 'principal'::character varying::text, 'late'::character varying::text, 'installment_interest'::character varying::text, 'inherited_installment_interest'::character varying::text, 'inherited_late'::character varying::text])) AND amount_cents <> 0", name: "abatements_valid"
  end

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

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agreement_bills", force: :cascade do |t|
    t.bigint "agreement_id", null: false
    t.bigint "bill_id", null: false
    t.bigint "contract_id", null: false
    t.jsonb "base", default: {}, null: false
    t.jsonb "discount", default: {}, null: false
    t.jsonb "credit", default: {}, null: false
    t.bigint "value_cents", null: false
    t.bigint "amount_cents", null: false
    t.bigint "paid_cents", null: false
    t.boolean "held", default: true, null: false
    t.index ["agreement_id"], name: "index_agreement_bills_on_agreement_id"
    t.index ["bill_id"], name: "index_agreement_bills_held_bill", unique: true, where: "held"
    t.index ["bill_id"], name: "index_agreement_bills_on_bill_id"
  end

  create_table "agreement_events", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "agreement_id", null: false
    t.bigint "user_id"
    t.string "kind", limit: 30, null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "occurred_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["agreement_id"], name: "index_agreement_events_on_agreement_id"
    t.index ["tenant_id", "occurred_at"], name: "index_agreement_events_on_tenant_id_and_occurred_at"
  end

  create_table "agreement_exports", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "user_id"
    t.string "form", limit: 10, null: false
    t.bigint "last_event_id", default: 0, null: false
    t.integer "lines", default: 0, null: false
    t.string "file_name", limit: 120
    t.datetime "downloaded_at"
    t.datetime "created_at", null: false
    t.index ["tenant_id", "created_at"], name: "index_agreement_exports_on_tenant_id_and_created_at"
    t.check_constraint "form::text = ANY (ARRAY['news'::character varying, 'full'::character varying, 'daily'::character varying]::text[])", name: "agreement_exports_form"
  end

  create_table "agreement_limits", force: :cascade do |t|
    t.bigint "segment_id", null: false
    t.bigint "profile_id", null: false
    t.jsonb "caps", default: {"cash" => {}, "installment" => {}}, null: false
    t.integer "max_installments", null: false
    t.integer "min_down_payment_pct", null: false
    t.bigint "ceiling_discount_cents"
    t.bigint "ceiling_value_cents"
    t.index ["profile_id"], name: "index_agreement_limits_on_profile_id"
    t.index ["segment_id", "profile_id"], name: "index_agreement_limits_on_segment_id_and_profile_id", unique: true
    t.check_constraint "max_installments >= 1 AND max_installments <= 120 AND min_down_payment_pct >= 1 AND min_down_payment_pct <= 100 AND (ceiling_discount_cents IS NULL OR ceiling_discount_cents >= 0) AND (ceiling_value_cents IS NULL OR ceiling_value_cents >= 0)", name: "agreement_limits_valid"
  end

  create_table "agreement_settlements", force: :cascade do |t|
    t.bigint "agreement_id", null: false
    t.bigint "user_id"
    t.date "on_date", null: false
    t.bigint "amount_cents", null: false
    t.jsonb "parts", default: {}, null: false
    t.datetime "expired_at"
    t.datetime "created_at", null: false
    t.index ["agreement_id"], name: "index_agreement_settlements_on_agreement_id"
  end

  create_table "agreements", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "customer_id", null: false
    t.bigint "segment_id"
    t.bigint "user_id"
    t.bigint "decided_by_id"
    t.string "number", limit: 20, null: false
    t.string "state", limit: 24, null: false
    t.string "mode", limit: 12, null: false
    t.date "built_on", null: false
    t.date "valid_until", null: false
    t.jsonb "discounts", default: {}, null: false
    t.bigint "base_cents", null: false
    t.bigint "discount_cents", null: false
    t.bigint "value_cents", null: false
    t.bigint "credit_cents", default: 0, null: false
    t.bigint "net_cents", null: false
    t.bigint "down_payment_cents", null: false
    t.date "down_payment_due", null: false
    t.integer "installments_count", default: 0, null: false
    t.integer "installment_day"
    t.string "installment_method", limit: 10, default: "none", null: false
    t.decimal "rate_pct", precision: 7, scale: 4, default: "0.0", null: false
    t.decimal "effective_annual_pct", precision: 9, scale: 4, default: "0.0", null: false
    t.bigint "total_cents", null: false
    t.bigint "interest_cents", default: 0, null: false
    t.jsonb "schedule", default: [], null: false
    t.jsonb "terms", default: {}, null: false
    t.datetime "decided_at"
    t.string "reason", limit: 300
    t.datetime "closed_at"
    t.bigint "replaced_by_id"
    t.string "presented_channel", limit: 12
    t.datetime "presented_at"
    t.string "accepted_channel", limit: 12
    t.datetime "accepted_at"
    t.string "proof", limit: 200
    t.bigint "accepted_by_customer_id"
    t.string "accepted_role", limit: 24
    t.bigint "registered_by_id"
    t.datetime "registered_at"
    t.jsonb "term_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "effectuated_at"
    t.string "effectuated_by", limit: 12
    t.datetime "broken_at"
    t.string "break_kind", limit: 20
    t.string "break_form", limit: 20
    t.boolean "broken_after_effectuation", default: false, null: false
    t.string "credit_mode", limit: 12
    t.bigint "credit_down_cents", default: 0, null: false
    t.datetime "reactivated_at"
    t.datetime "reversing_since"
    t.string "reversal_reason", limit: 300
    t.bigint "reversal_by_id"
    t.datetime "reverted_at"
    t.index ["customer_id"], name: "index_agreements_broken_after_effectuation", where: "broken_after_effectuation"
    t.index ["customer_id"], name: "index_agreements_on_customer_id"
    t.index ["tenant_id", "created_at"], name: "index_agreements_on_tenant_id_and_created_at"
    t.index ["tenant_id", "number"], name: "index_agreements_on_tenant_id_and_number", unique: true
    t.index ["tenant_id", "state", "valid_until"], name: "index_agreements_on_tenant_id_and_state_and_valid_until"
    t.check_constraint "(mode::text = ANY (ARRAY['cash'::character varying, 'installments'::character varying]::text[])) AND (installment_method::text = ANY (ARRAY['none'::character varying, 'price'::character varying, 'sac'::character varying]::text[])) AND installments_count >= 0 AND base_cents > 0 AND discount_cents >= 0 AND value_cents > 0 AND net_cents > 0 AND down_payment_cents > 0 AND down_payment_cents <= net_cents", name: "agreements_valid"
    t.check_constraint "break_kind IS NULL OR (break_kind::text = ANY (ARRAY['before_effectuation'::character varying, 'after_effectuation'::character varying, 'manual'::character varying]::text[]))", name: "agreements_break_kind"
    t.check_constraint "effectuated_by IS NULL OR (effectuated_by::text = ANY (ARRAY['payment'::character varying, 'acceptance'::character varying, 'credit'::character varying]::text[]))", name: "agreements_effectuated_by"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying, 'approved'::character varying, 'refused'::character varying, 'not_approved'::character varying, 'expired'::character varying, 'canceled'::character varying, 'awaiting_effectuation'::character varying, 'active_on_time'::character varying, 'active_late'::character varying, 'settled'::character varying, 'broken'::character varying, 'renegotiated'::character varying]::text[])", name: "agreements_state"
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
    t.string "kind", limit: 10, default: "common", null: false
    t.bigint "agreement_id"
    t.jsonb "composition"
    t.bigint "origin_agreement_id"
    t.index ["agreement_id"], name: "index_bills_on_agreement", where: "(agreement_id IS NOT NULL)"
    t.index ["contract_id"], name: "index_bills_on_contract_id"
    t.index ["customer_id"], name: "index_bills_on_customer_id"
    t.index ["origin_agreement_id"], name: "index_bills_on_origin_agreement_id", where: "(origin_agreement_id IS NOT NULL)"
    t.index ["tenant_id", "customer_id", "number"], name: "index_bills_on_tenant_id_and_customer_id_and_number", unique: true
    t.index ["tenant_id", "status", "due_date"], name: "index_bills_on_tenant_id_and_status_and_due_date"
    t.index ["tenant_id"], name: "index_bills_with_excess_by_tenant", where: "(paid_cents > amount_cents)"
    t.check_constraint "(kind::text = ANY (ARRAY['common'::character varying, 'agreement'::character varying, 'break'::character varying, 'reversal'::character varying]::text[])) AND (kind::text = ANY (ARRAY['agreement'::character varying, 'break'::character varying]::text[])) = (agreement_id IS NOT NULL) AND (kind::text = 'reversal'::text) = (origin_agreement_id IS NOT NULL)", name: "bills_kind"
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
    t.bigint "agreement_id"
    t.string "bucket", limit: 10, default: "available", null: false
    t.bigint "bill_id"
    t.index ["agreement_id"], name: "index_credits_on_agreement_id", where: "(agreement_id IS NOT NULL)"
    t.index ["bill_id"], name: "index_credits_on_bill_id", where: "(bill_id IS NOT NULL)"
    t.index ["contract_id", "bucket"], name: "index_credits_on_contract_and_bucket"
    t.index ["contract_id"], name: "index_credits_on_contract_id"
    t.index ["tenant_id"], name: "index_credits_on_tenant_id"
    t.check_constraint "amount_cents <> 0", name: "credits_amount_not_zero"
    t.check_constraint "bucket::text = ANY (ARRAY['available'::character varying, 'awaiting'::character varying, 'blocked'::character varying]::text[])", name: "credits_bucket"
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
    t.check_constraint "kind::text = ANY (ARRAY['phone'::character varying, 'email'::character varying, 'address'::character varying]::text[])", name: "customer_contacts_kind"
    t.check_constraint "status::text = ANY (ARRAY['valid'::character varying, 'invalid'::character varying, 'do_not_disturb'::character varying]::text[])", name: "customer_contacts_status"
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

  create_table "holidays", force: :cascade do |t|
    t.string "state", limit: 2, null: false
    t.bigint "municipality_id"
    t.date "date", null: false
    t.string "name", limit: 150, null: false
    t.index ["date"], name: "index_holidays_on_date"
    t.index ["state", "municipality_id", "date"], name: "index_holidays_on_state_and_municipality_id_and_date", unique: true, nulls_not_distinct: true
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
    t.index ["import_id", "document"], name: "index_import_contacts_on_import_id_and_document"
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
    t.jsonb "batch_state"
    t.index ["tenant_id", "status"], name: "index_imports_on_tenant_id_and_status"
    t.index ["tenant_id"], name: "index_imports_one_running_per_tenant", unique: true, where: "((status)::text = ANY ((ARRAY['received'::character varying, 'checking'::character varying, 'checked'::character varying, 'confirming'::character varying])::text[]))"
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
    t.check_constraint "series::text = ANY (ARRAY['ipca'::character varying, 'inpc'::character varying, 'igpm'::character varying, 'selic'::character varying, 'legal'::character varying]::text[])", name: "index_adjustments_series"
  end

  create_table "index_rates", force: :cascade do |t|
    t.string "series", limit: 10, null: false
    t.date "month", null: false
    t.decimal "value", precision: 11, scale: 6, null: false
    t.boolean "partial", default: false, null: false
    t.datetime "fetched_at", null: false
    t.index ["series", "month"], name: "index_index_rates_on_series_and_month", unique: true
    t.check_constraint "series::text = ANY (ARRAY['ipca'::character varying, 'inpc'::character varying, 'igpm'::character varying, 'selic'::character varying, 'legal'::character varying]::text[])", name: "index_rates_series"
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

  create_table "municipalities", force: :cascade do |t|
    t.string "ibge_code", limit: 7, null: false
    t.string "name", limit: 120, null: false
    t.string "name_key", limit: 120, null: false
    t.string "state", limit: 2, null: false
    t.index ["ibge_code"], name: "index_municipalities_on_ibge_code", unique: true
    t.index ["state", "name_key"], name: "index_municipalities_on_state_and_name_key", unique: true
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

  create_table "payment_accounts", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "channel_id", null: false
    t.string "modality", limit: 10, null: false
    t.string "provider", limit: 30, null: false
    t.string "environment", limit: 12, null: false
    t.string "nickname", limit: 100, null: false
    t.boolean "active", default: true, null: false
    t.jsonb "config", default: {}, null: false
    t.text "secrets"
    t.jsonb "file_details", default: {}, null: false
    t.datetime "webhook_previous_until"
    t.date "certificate_warned_for"
    t.datetime "last_tested_at"
    t.string "last_test_status", limit: 10
    t.string "last_test_message", limit: 300
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id"], name: "index_payment_accounts_on_channel_id"
    t.index ["tenant_id", "modality", "environment"], name: "index_payment_accounts_active_unique", unique: true, where: "active"
    t.index ["tenant_id", "nickname"], name: "index_payment_accounts_on_tenant_id_and_nickname", unique: true
    t.check_constraint "environment::text = ANY (ARRAY['sandbox'::character varying, 'production'::character varying]::text[])", name: "payment_accounts_environment"
    t.check_constraint "last_test_status IS NULL OR (last_test_status::text = ANY (ARRAY['ok'::character varying, 'failed'::character varying]::text[]))", name: "payment_accounts_test_status"
    t.check_constraint "modality::text = ANY (ARRAY['boleto'::character varying, 'pix'::character varying, 'card'::character varying]::text[])", name: "payment_accounts_modality"
  end

  create_table "payment_allocations", force: :cascade do |t|
    t.bigint "payment_id", null: false
    t.bigint "bill_id", null: false
    t.string "component", limit: 40, null: false
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.index ["bill_id"], name: "index_payment_allocations_on_bill_id"
    t.index ["payment_id"], name: "index_payment_allocations_on_payment_id"
    t.check_constraint "component::text = ANY (ARRAY['interest'::character varying::text, 'fine'::character varying::text, 'fees'::character varying::text, 'correction'::character varying::text, 'principal'::character varying::text, 'late'::character varying::text, 'installment_interest'::character varying::text, 'inherited_installment_interest'::character varying::text, 'inherited_late'::character varying::text])", name: "payment_allocations_component"
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

  create_table "payment_checkouts", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "customer_id"
    t.string "token", limit: 64, null: false
    t.string "state", limit: 20, default: "open", null: false
    t.string "environment", limit: 10, default: "production", null: false
    t.bigint "amount_cents", null: false
    t.string "description", limit: 200
    t.string "modalities", default: [], null: false, array: true
    t.string "highlight", limit: 10
    t.datetime "expires_at", null: false
    t.string "payer_name", limit: 300
    t.string "payer_document", limit: 14
    t.jsonb "payer_address", default: {}, null: false
    t.string "payer_email", limit: 254
    t.string "payer_phone", limit: 20
    t.string "reference_type", limit: 40
    t.bigint "reference_id"
    t.integer "access_count", default: 0, null: false
    t.datetime "last_accessed_at"
    t.jsonb "result", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_payment_checkouts_on_customer_id", where: "(customer_id IS NOT NULL)"
    t.index ["tenant_id", "created_at"], name: "index_payment_checkouts_on_tenant_id_and_created_at"
    t.index ["token"], name: "index_payment_checkouts_on_token", unique: true
    t.check_constraint "amount_cents > 0", name: "payment_checkouts_amount"
    t.check_constraint "state::text = ANY (ARRAY['open'::character varying, 'card_approved'::character varying, 'paid'::character varying, 'card_unconfirmed'::character varying, 'canceled'::character varying]::text[])", name: "payment_checkouts_state"
  end

  create_table "payment_events", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "account_id", null: false
    t.bigint "instrument_id"
    t.string "event_id", limit: 200, null: false
    t.string "kind", limit: 20, null: false
    t.string "external_id", limit: 100
    t.bigint "amount_cents"
    t.datetime "occurred_at"
    t.string "previous_status", limit: 40
    t.string "current_status", limit: 40
    t.jsonb "summary", default: {}, null: false
    t.string "state", limit: 10, default: "received", null: false
    t.string "outcome", limit: 300
    t.integer "attempts", default: 0, null: false
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "event_id"], name: "index_payment_events_on_account_and_event_id", unique: true
    t.index ["instrument_id"], name: "index_payment_events_on_instrument_id", where: "(instrument_id IS NOT NULL)"
    t.index ["tenant_id", "created_at"], name: "index_payment_events_pending", where: "((state)::text = ANY ((ARRAY['received'::character varying, 'failed'::character varying])::text[]))"
    t.check_constraint "kind::text = ANY (ARRAY['paid'::character varying, 'refunded'::character varying, 'canceled'::character varying, 'expired'::character varying, 'check'::character varying, 'other'::character varying]::text[])", name: "payment_events_kind"
    t.check_constraint "state::text = ANY (ARRAY['received'::character varying, 'applied'::character varying, 'ignored'::character varying, 'review'::character varying, 'failed'::character varying]::text[])", name: "payment_events_state"
  end

  create_table "payment_instruments", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "account_id", null: false
    t.string "provider", limit: 30, null: false
    t.bigint "customer_id"
    t.string "kind", limit: 10, null: false
    t.string "state", limit: 10, default: "emitting", null: false
    t.bigint "amount_cents", null: false
    t.date "due_on", null: false
    t.string "external_id", limit: 100
    t.string "custom_id", limit: 35, null: false
    t.string "payer_name", limit: 300
    t.string "payer_document", limit: 14
    t.jsonb "payer_address", default: {}, null: false
    t.string "reference_type", limit: 40
    t.bigint "reference_id"
    t.string "digitable_line", limit: 60
    t.text "copy_paste"
    t.string "boleto_pdf_sha256", limit: 64
    t.string "pix_qr_sha256", limit: 64
    t.string "failure_reason", limit: 300
    t.jsonb "response_summary", default: {}, null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "issued_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "checkout_id"
    t.bigint "payment_id"
    t.datetime "paid_at"
    t.bigint "paid_cents"
    t.bigint "refunded_cents", default: 0, null: false
    t.datetime "reconciled_at"
    t.index ["account_id", "external_id"], name: "index_payment_instruments_on_account_and_external_id", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["account_id"], name: "index_payment_instruments_on_account_id"
    t.index ["checkout_id"], name: "index_payment_instruments_on_checkout_id", where: "(checkout_id IS NOT NULL)"
    t.index ["customer_id"], name: "index_payment_instruments_on_customer_id", where: "(customer_id IS NOT NULL)"
    t.index ["payment_id"], name: "index_payment_instruments_on_payment_id", where: "(payment_id IS NOT NULL)"
    t.index ["tenant_id", "custom_id"], name: "index_payment_instruments_on_tenant_id_and_custom_id", unique: true
    t.index ["tenant_id", "reconciled_at"], name: "index_payment_instruments_to_reconcile", where: "((state)::text = 'active'::text)"
    t.check_constraint "amount_cents > 0", name: "payment_instruments_amount"
    t.check_constraint "kind::text = ANY (ARRAY['boleto'::character varying, 'pix'::character varying, 'card'::character varying]::text[])", name: "payment_instruments_kind"
    t.check_constraint "state::text = ANY (ARRAY['emitting'::character varying, 'active'::character varying, 'paid'::character varying, 'expired'::character varying, 'canceled'::character varying, 'failed'::character varying]::text[])", name: "payment_instruments_state"
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
    t.boolean "grace_free", default: false, null: false
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
    t.string "final_state", limit: 10
    t.integer "rank", limit: 2, default: 3, null: false
    t.bigint "pending_payment_id"
    t.index ["import_id", "channel_code", "identifier"], name: "idx_on_import_id_channel_code_identifier_ab3d619076"
    t.index ["import_id", "line"], name: "index_payment_rows_on_import_id_and_line", unique: true
    t.index ["import_id", "ok", "paid_on", "rank", "line"], name: "index_payment_rows_on_stream_order"
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
    t.string "final_state", limit: 10
    t.bigint "agreement_id"
    t.bigint "moved_to_credit_cents", default: 0, null: false
    t.index ["agreement_id"], name: "index_payments_on_agreement_id", where: "(agreement_id IS NOT NULL)"
    t.index ["bill_id"], name: "index_payments_on_bill_id"
    t.index ["tenant_id", "channel_id", "identifier"], name: "index_payments_on_tenant_id_and_channel_id_and_identifier", unique: true
    t.index ["tenant_id", "paid_on"], name: "index_payments_on_tenant_id_and_paid_on"
    t.index ["tenant_id"], name: "index_payments_pending_by_tenant", where: "((status)::text = 'pending'::text)"
    t.check_constraint "amount_cents > 0", name: "payments_amount_positive"
    t.check_constraint "applied_cents >= 0 AND credit_cents >= 0 AND reversed_cents >= 0 AND credit_reversed_cents >= 0", name: "payments_parts_not_negative"
    t.check_constraint "moved_to_credit_cents >= 0", name: "payments_moved_to_credit"
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

  create_table "reversal_waits", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "payment_id", null: false
    t.bigint "agreement_id"
    t.bigint "contract_id", null: false
    t.bigint "amount_cents", null: false
    t.string "reason", limit: 30, null: false
    t.date "reversed_on", null: false
    t.date "processed_on", null: false
    t.string "state", limit: 10, default: "waiting", null: false
    t.string "decision", limit: 20
    t.bigint "decided_by_id"
    t.datetime "decided_at"
    t.string "note", limit: 300
    t.jsonb "details", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["agreement_id"], name: "index_reversal_waits_on_agreement_id", where: "(agreement_id IS NOT NULL)"
    t.index ["payment_id"], name: "index_reversal_waits_on_payment_id"
    t.index ["tenant_id", "state", "created_at"], name: "index_reversal_waits_on_tenant_state"
    t.check_constraint "(state::text = ANY (ARRAY['waiting'::character varying, 'decided'::character varying]::text[])) AND amount_cents > 0 AND (decision IS NULL OR (decision::text = ANY (ARRAY['reopen'::character varying, 'reversal_title'::character varying, 'credit'::character varying, 'revert'::character varying]::text[])))", name: "reversal_waits_valid"
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
    t.decimal "installment_rate_pct", precision: 7, scale: 4
    t.string "installment_method", limit: 10
    t.string "agreement_days_convention", limit: 10
    t.string "agreement_fine_base", limit: 10
    t.jsonb "agreement_caps", default: {"cash" => {}, "installment" => {}}, null: false
    t.integer "agreement_max_installments", default: 12, null: false
    t.bigint "agreement_min_installment_cents", default: 5000, null: false
    t.integer "agreement_min_down_payment_pct", default: 10, null: false
    t.integer "agreement_down_payment_days", default: 10, null: false
    t.integer "agreement_validity_days", default: 5, null: false
    t.integer "agreement_tolerance_days", default: 3, null: false
    t.integer "agreement_break_days", default: 30, null: false
    t.index ["tenant_id", "name_key"], name: "index_segments_on_tenant_id_and_name_key", unique: true
    t.index ["tenant_id"], name: "index_segments_one_catch_all_per_tenant", unique: true, where: "catch_all"
    t.check_constraint "(fine_pct IS NULL OR fine_pct >= 0::numeric AND fine_pct <= 100::numeric) AND (interest_pct IS NULL OR interest_pct >= 0::numeric AND interest_pct <= 100::numeric) AND fees_pct >= 0::numeric AND fees_pct <= 100::numeric", name: "segments_charge_pct"
    t.check_constraint "(index_code IS NULL OR (index_code::text = ANY (ARRAY['none'::character varying, 'ipca'::character varying, 'inpc'::character varying, 'igpm'::character varying]::text[]))) AND (days_convention IS NULL OR (days_convention::text = ANY (ARRAY['calendar'::character varying, 'thirty'::character varying]::text[]))) AND (fine_base IS NULL OR (fine_base::text = ANY (ARRAY['corrected'::character varying, 'face'::character varying]::text[])))", name: "segments_charge_options"
    t.check_constraint "(installment_rate_pct IS NULL OR installment_rate_pct >= 0::numeric AND installment_rate_pct <= 100::numeric) AND (installment_method IS NULL OR (installment_method::text = ANY (ARRAY['none'::character varying, 'price'::character varying, 'sac'::character varying]::text[]))) AND (agreement_days_convention IS NULL OR (agreement_days_convention::text = ANY (ARRAY['calendar'::character varying, 'thirty'::character varying]::text[]))) AND (agreement_fine_base IS NULL OR (agreement_fine_base::text = ANY (ARRAY['corrected'::character varying, 'face'::character varying]::text[])))", name: "segments_agreement_params"
    t.check_constraint "(interest_kind::text = ANY (ARRAY['none'::character varying, 'fixed'::character varying, 'legal'::character varying]::text[])) AND (interest_form::text = ANY (ARRAY['simple'::character varying, 'compound'::character varying]::text[]))", name: "segments_interest"
    t.check_constraint "agreement_max_installments >= 1 AND agreement_max_installments <= 120 AND agreement_min_installment_cents >= 0 AND agreement_min_down_payment_pct >= 1 AND agreement_min_down_payment_pct <= 100 AND agreement_down_payment_days >= 1 AND agreement_down_payment_days <= 365 AND agreement_validity_days >= 1 AND agreement_validity_days <= 365 AND agreement_tolerance_days >= 0 AND agreement_tolerance_days <= 60 AND agreement_break_days >= 1 AND agreement_break_days <= 365", name: "segments_agreement_variables"
    t.check_constraint "broke_agreement IS NULL OR (broke_agreement::text = ANY (ARRAY['yes'::character varying, 'no'::character varying]::text[]))", name: "segments_broke_agreement"
    t.check_constraint "person_type IS NULL OR (person_type::text = ANY (ARRAY['person'::character varying, 'company'::character varying, 'mixed'::character varying]::text[]))", name: "segments_person_type"
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
    t.decimal "installment_rate_pct", precision: 7, scale: 4, default: "0.0", null: false
    t.string "installment_method", limit: 10, default: "none", null: false
    t.string "agreement_days_convention", limit: 10, default: "thirty", null: false
    t.string "agreement_fine_base", limit: 10, default: "corrected", null: false
    t.jsonb "agreement_policies", default: {}, null: false
    t.integer "agreement_sequence", default: 0, null: false
    t.index ["tenant_id"], name: "index_tenant_settings_on_tenant_id", unique: true
    t.check_constraint "(charge_days_convention::text = ANY (ARRAY['calendar'::character varying, 'thirty'::character varying]::text[])) AND (charge_fine_base::text = ANY (ARRAY['corrected'::character varying, 'face'::character varying]::text[]))", name: "tenant_settings_charge_conventions"
    t.check_constraint "(missing_index_policy::text = ANY (ARRAY['closed_only'::character varying, 'last_prorated'::character varying]::text[])) AND (default_interest_form::text = ANY (ARRAY['simple'::character varying, 'compound'::character varying]::text[])) AND (negative_index_policy::text = ANY (ARRAY['floor'::character varying, 'always'::character varying, 'ignore'::character varying]::text[])) AND (old_legal_interest_policy::text = ANY (ARRAY['selic'::character varying, 'one_percent'::character varying, 'none'::character varying]::text[])) AND (surcharge_comparison_policy::text = ANY (ARRAY['before'::character varying, 'after'::character varying]::text[]))", name: "tenant_settings_charge_policies"
    t.check_constraint "(promise_counting::text = ANY (ARRAY['promise_only'::character varying, 'also_direct'::character varying]::text[])) AND (promise_after_break::text = ANY (ARRAY['fulfilled'::character varying, 'stays_broken'::character varying]::text[])) AND (promise_partial::text = ANY (ARRAY['prevails'::character varying, 'r46'::character varying]::text[]))", name: "tenant_settings_promise_policies"
    t.check_constraint "charge_fine_pct >= 0::numeric AND charge_fine_pct <= 100::numeric AND charge_interest_pct >= 0::numeric AND charge_interest_pct <= 100::numeric", name: "tenant_settings_charge_pct"
    t.check_constraint "charge_index::text = ANY (ARRAY['none'::character varying, 'ipca'::character varying, 'inpc'::character varying, 'igpm'::character varying]::text[])", name: "tenant_settings_charge_index"
    t.check_constraint "installment_rate_pct >= 0::numeric AND installment_rate_pct <= 100::numeric AND (installment_method::text = ANY (ARRAY['none'::character varying, 'price'::character varying, 'sac'::character varying]::text[])) AND (agreement_days_convention::text = ANY (ARRAY['calendar'::character varying, 'thirty'::character varying]::text[])) AND (agreement_fine_base::text = ANY (ARRAY['corrected'::character varying, 'face'::character varying]::text[]))", name: "tenant_settings_agreement_params"
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

  add_foreign_key "abatements", "bills"
  add_foreign_key "abatements", "payments"
  add_foreign_key "abatements", "tenants"
  add_foreign_key "access_events", "tenants", on_delete: :nullify
  add_foreign_key "access_events", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "access_events", "users", on_delete: :nullify
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agreement_bills", "agreements", on_delete: :cascade
  add_foreign_key "agreement_bills", "bills", on_delete: :restrict
  add_foreign_key "agreement_bills", "contracts", on_delete: :restrict
  add_foreign_key "agreement_events", "agreements", on_delete: :cascade
  add_foreign_key "agreement_events", "tenants"
  add_foreign_key "agreement_events", "users", on_delete: :nullify
  add_foreign_key "agreement_exports", "tenants"
  add_foreign_key "agreement_exports", "users", on_delete: :nullify
  add_foreign_key "agreement_limits", "profiles", on_delete: :cascade
  add_foreign_key "agreement_limits", "segments", on_delete: :cascade
  add_foreign_key "agreement_settlements", "agreements", on_delete: :cascade
  add_foreign_key "agreement_settlements", "users", on_delete: :nullify
  add_foreign_key "agreements", "customers", column: "accepted_by_customer_id", on_delete: :nullify
  add_foreign_key "agreements", "customers", on_delete: :restrict
  add_foreign_key "agreements", "segments", on_delete: :nullify
  add_foreign_key "agreements", "tenants"
  add_foreign_key "agreements", "users", column: "decided_by_id", on_delete: :nullify
  add_foreign_key "agreements", "users", column: "registered_by_id", on_delete: :nullify
  add_foreign_key "agreements", "users", column: "reversal_by_id", on_delete: :nullify
  add_foreign_key "agreements", "users", on_delete: :nullify
  add_foreign_key "bill_valuations", "bills", on_delete: :cascade
  add_foreign_key "bill_valuations", "tenants"
  add_foreign_key "bill_value_versions", "bills", on_delete: :restrict
  add_foreign_key "bill_value_versions", "imports", on_delete: :nullify
  add_foreign_key "bill_value_versions", "tenants"
  add_foreign_key "bill_value_versions", "users", on_delete: :nullify
  add_foreign_key "bills", "agreements", column: "origin_agreement_id", on_delete: :restrict
  add_foreign_key "bills", "agreements", on_delete: :restrict
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
  add_foreign_key "credits", "agreements", on_delete: :restrict
  add_foreign_key "credits", "bills", on_delete: :restrict
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
  add_foreign_key "holidays", "municipalities", on_delete: :cascade
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
  add_foreign_key "payment_accounts", "payment_channels", column: "channel_id"
  add_foreign_key "payment_accounts", "tenants"
  add_foreign_key "payment_allocations", "bills", on_delete: :restrict
  add_foreign_key "payment_allocations", "payments", on_delete: :restrict
  add_foreign_key "payment_channels", "tenants"
  add_foreign_key "payment_checkouts", "customers"
  add_foreign_key "payment_checkouts", "tenants"
  add_foreign_key "payment_events", "payment_accounts", column: "account_id"
  add_foreign_key "payment_events", "payment_instruments", column: "instrument_id"
  add_foreign_key "payment_events", "tenants"
  add_foreign_key "payment_instruments", "customers"
  add_foreign_key "payment_instruments", "payment_accounts", column: "account_id"
  add_foreign_key "payment_instruments", "payment_checkouts", column: "checkout_id"
  add_foreign_key "payment_instruments", "payments", on_delete: :nullify
  add_foreign_key "payment_instruments", "tenants"
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
  add_foreign_key "payments", "agreements", on_delete: :restrict
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
  add_foreign_key "reversal_waits", "agreements", on_delete: :restrict
  add_foreign_key "reversal_waits", "contracts"
  add_foreign_key "reversal_waits", "payments", on_delete: :restrict
  add_foreign_key "reversal_waits", "tenants"
  add_foreign_key "reversal_waits", "users", column: "decided_by_id", on_delete: :nullify
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
