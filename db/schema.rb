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

ActiveRecord::Schema[8.1].define(version: 2026_10_29_000010) do
  create_table "access_document", charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.column "type", "enum('gift_ticket','lsd_ticket','special_price_ticket','staff_credential','vehicle_pass_sp','vehicle_pass_gift','vehicle_pass_lsd','work_access_pass','work_access_pass_so')", null: false
    t.column "status", "enum('qualified','claimed','banked','used','cancelled','expired','submitted','turned_down')", default: "qualified", null: false
    t.integer "source_year"
    t.datetime "access_date", precision: nil
    t.boolean "access_any_time", default: false
    t.text "name"
    t.text "comments"
    t.date "expiry_date"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, default: -> { "current_timestamp()" }, null: false
    t.column "delivery_method", "enum('none','postal','email','will_call','priority')", null: false
    t.string "street1", limit: 191, default: "", null: false
    t.string "street2", limit: 191, default: "", null: false
    t.string "city", limit: 191, default: "", null: false
    t.string "state", limit: 191, default: "", null: false
    t.string "postal_code", limit: 191, default: "", null: false
    t.string "country", limit: 191, default: "", null: false
    t.index ["person_id", "source_year"], name: "access_document_person_id_source_year_index"
    t.index ["person_id", "status"], name: "access_document_person_id_status_index"
    t.index ["person_id", "type"], name: "person_id"
    t.index ["status", "source_year"], name: "access_document_status_source_year_index"
    t.index ["type", "status"], name: "access_document_type_status_index"
  end

  create_table "access_document_changes", charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.string "table_name", limit: 32, null: false
    t.integer "record_id", null: false
    t.column "operation", "enum('create','modify','delete')", null: false
    t.text "changes"
    t.integer "changer_person_id", null: false
    t.datetime "created_at", precision: nil, default: -> { "current_timestamp()" }, null: false
    t.index ["record_id"], name: "index_access_document_changes_on_record_id"
  end

  create_table "action_logs", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.integer "person_id", unsigned: true
    t.integer "target_person_id", unsigned: true
    t.string "event", limit: 191, null: false
    t.text "message", null: false
    t.text "data", size: :long
    t.timestamp "created_at", default: -> { "current_timestamp()" }, null: false
    t.string "ip", limit: 191
    t.string "user_agent", limit: 191
    t.index ["created_at", "id"], name: "created_at_id_idx"
    t.index ["event"], name: "action_logs_event"
    t.index ["person_id", "created_at"], name: "action_logs_person_id_created_at_index"
    t.index ["person_id", "event", "created_at"], name: "action_logs_person_id_event_created_at_index"
    t.index ["target_person_id", "created_at"], name: "action_logs_target_person_id_created_at_index"
  end

  create_table "active_storage_attachments", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
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

  create_table "active_storage_variant_records", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "alert", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "title"
    t.text "description", size: :medium
    t.boolean "on_playa", default: false, null: false
    t.timestamp "created_at", default: -> { "current_timestamp()" }, null: false
    t.timestamp "updated_at", default: -> { "current_timestamp() ON UPDATE current_timestamp()" }, null: false
  end

  create_table "asset", charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.string "type"
    t.string "barcode", limit: 25, null: false
    t.string "description", limit: 25, comment: "placed by staff"
    t.boolean "perm_assign", default: false, null: false, comment: "assigned \"permanently\" to a person?"
    t.datetime "created_at", precision: nil, default: -> { "current_timestamp()" }, null: false
    t.string "group_name", limit: 25
    t.text "notes"
    t.integer "year", default: 0, null: false
    t.date "expires_on"
    t.string "order_number"
    t.string "entity_assignment"
    t.index ["order_number", "year"], name: "asset_order_number_year_index"
    t.index ["type", "year", "barcode"], name: "asset_type_year_barcode_index"
    t.index ["year", "barcode"], name: "asset_year_barcode_index"
  end

  create_table "asset_attachment", id: { type: :bigint, unsigned: true, default: nil }, charset: "utf8mb3", collation: "utf8mb3_general_ci", force: :cascade do |t|
    t.column "parent_type", "enum('Radio','Vehicle')", null: false
    t.string "description", limit: 32, null: false
  end

  create_table "award", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "title", null: false
    t.text "description", null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.boolean "awards_grants_service_year", default: false, null: false
  end

  create_table "bmid", id: { type: :bigint, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.column "status", "enum('in_prep','do_not_print','ready_to_print','ready_to_reprint_lost','ready_to_reprint_changed','issues','submitted')"
    t.integer "year", default: 0, null: false
    t.string "title1", limit: 64
    t.string "title2", limit: 64
    t.string "title3", limit: 64
    t.boolean "showers", default: false
    t.boolean "org_vehicle_insurance", default: false
    t.column "meals", "enum('all','pre','post','event','pre+event','event+post','pre+post')"
    t.string "batch", limit: 128
    t.text "team"
    t.text "notes"
    t.datetime "created_at", precision: nil, default: -> { "current_timestamp()" }, null: false
    t.datetime "updated_at", precision: nil, default: -> { "current_timestamp()" }, null: false
    t.index ["person_id", "year"], name: "person_id", unique: true
  end

  create_table "bmid_export", id: :integer, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "filename", limit: 191, null: false
    t.string "batch_info", limit: 191, null: false
    t.text "person_ids", null: false
    t.integer "person_id", null: false
    t.datetime "created_at", precision: nil, null: false
  end

  create_table "bmid_title", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "title", limit: 64, null: false
    t.integer "title_line", limit: 2, null: false
    t.integer "sort_index", limit: 2, null: false
    t.bigint "position_id", null: false, unsigned: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["position_id", "title_line"], name: "index_bmid_title_on_position_id_and_title_line", unique: true
  end

  create_table "broadcast", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "sender_id", null: false
    t.bigint "alert_id", null: false
    t.string "sms_message", limit: 1600
    t.string "sender_address"
    t.text "email_message", size: :medium
    t.string "subject"
    t.boolean "sent_sms", default: false, null: false
    t.boolean "sent_email", default: false, null: false
    t.boolean "sent_clubhouse", default: false, null: false
    t.integer "recipient_count", default: 0, null: false
    t.integer "sms_failed", default: 0, null: false
    t.integer "email_failed", default: 0, null: false
    t.timestamp "created_at", default: -> { "current_timestamp()" }
    t.datetime "retry_at", precision: nil
    t.bigint "retry_person_id"
    t.datetime "expires_at", precision: nil
    t.index ["alert_id"], name: "fk_rails_13463f4240"
    t.index ["sender_id"], name: "sender_id"
  end

  create_table "broadcast_message", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id"
    t.bigint "broadcast_id"
    t.column "direction", "enum('inbound','outbound')", default: "outbound"
    t.string "status", limit: 32, null: false
    t.string "address_type", limit: 32
    t.string "address", null: false
    t.text "message", size: :medium
    t.timestamp "created_at", default: -> { "current_timestamp()" }, null: false
    t.string "message_id", comment: "the id SES gave this email (mail_log.message_id holds the same), or the SID Twilio gave this text"
    t.index ["broadcast_id"], name: "broadcast_id"
    t.index ["person_id"], name: "person_id"
  end

  create_table "bug_report", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.text "description", null: false
    t.string "url"
    t.string "ip", limit: 45
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.index ["person_id"], name: "index_bug_report_on_person_id"
  end

  create_table "certification", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "title", null: false
    t.string "sl_title"
    t.boolean "on_sl_report", default: false, null: false
    t.text "description"
    t.boolean "is_lifetime_certification", default: false, null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.index ["on_sl_report"], name: "certification_on_sl_report_index"
  end

  create_table "contact_log", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "sender_person_id", null: false
    t.bigint "recipient_person_id", null: false
    t.string "action", null: false
    t.datetime "sent_at", precision: nil, default: -> { "current_timestamp()" }
    t.string "recipient_address", null: false
    t.string "subject"
    t.text "message", size: :medium
    t.index ["recipient_person_id", "sent_at"], name: "recipient_person_id"
    t.index ["sender_person_id", "sent_at"], name: "sender_person_id"
  end

  create_table "document", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "tag", limit: 191, null: false
    t.string "description", limit: 191, null: false
    t.text "body", size: :long, null: false
    t.integer "person_create_id", null: false
    t.integer "person_update_id", null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.integer "refresh_time"
    t.index ["tag"], name: "document_tag_unique", unique: true
  end

  create_table "email_history", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.integer "source_person_id"
    t.string "email", null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.index ["email"], name: "email_history_email_index"
    t.index ["person_id"], name: "email_history_person_id_index"
    t.index ["source_person_id"], name: "email_history_source_person_id_index"
  end

  create_table "email_suppression", charset: "utf8mb4", collation: "utf8mb4_general_ci", comment: "addresses that bounced for good or reported Clubhouse email as spam", force: :cascade do |t|
    t.string "email", null: false
    t.column "reason", "enum('bounce','complaint')", null: false
    t.string "sub_type", comment: "the latest report's bounceSubType or complaintSubType"
    t.datetime "first_reported_at", null: false
    t.datetime "last_reported_at", null: false
    t.integer "report_count", default: 1, null: false
    t.string "message_id", comment: "the id SES gave the email the latest report was about"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_email_suppression_on_email", unique: true
  end

  create_table "error_logs", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "error_type", limit: 191, null: false
    t.text "url"
    t.integer "person_id", unsigned: true
    t.string "ip", limit: 191
    t.string "user_agent", limit: 191
    t.text "data", size: :long
    t.timestamp "created_at", default: -> { "current_timestamp()" }, null: false
    t.index ["person_id", "created_at"], name: "error_logs_person_id_created_at_index"
  end

  create_table "event_dates", id: { type: :integer, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "event_start", precision: nil
    t.datetime "event_end", precision: nil
    t.datetime "pre_event_start", precision: nil
    t.datetime "post_event_end", precision: nil
    t.datetime "pre_event_slot_start", precision: nil
    t.datetime "pre_event_slot_end", precision: nil
  end

  create_table "handle_reservation", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "handle", null: false
    t.column "reservation_type", "enum('brc_term','deceased_person','dismissed_person','obscene','phonetic-alphabet','radio_jargon','ranger_term','slur','twii_person','uncategorized')", default: "uncategorized", null: false
    t.date "expires_on"
    t.string "reason"
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.integer "twii_year"
    t.string "normalized_handle", default: "", null: false
    t.index ["expires_on"], name: "index_handle_reservation_on_expires_on"
    t.index ["normalized_handle", "reservation_type", "twii_year"], name: "index_handle_reservation_on_lookup_key"
    t.index ["reservation_type", "twii_year"], name: "index_handle_reservation_on_type_and_year"
  end

  create_table "help", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "slug", limit: 128, null: false
    t.string "title", limit: 128, null: false
    t.text "body", null: false
    t.string "tags", default: ""
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.index ["slug"], name: "slug", unique: true
  end

  create_table "help_hit", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.integer "help_id", null: false, unsigned: true
    t.integer "person_id", unsigned: true
    t.timestamp "created_at", default: -> { "current_timestamp()" }, null: false
    t.index ["help_id", "created_at"], name: "help_hit_help_id_created_at_index"
  end

  create_table "legacy_log", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "log_id", null: false, unsigned: true
    t.integer "person_id", unsigned: true
    t.integer "target_person_id", unsigned: true
    t.string "event", limit: 191, null: false
    t.text "data", size: :long
    t.datetime "created_at", precision: nil, null: false
    t.index ["created_at", "id"], name: "index_legacy_log_on_created_at_and_id"
    t.index ["event"], name: "index_legacy_log_on_event"
    t.index ["log_id"], name: "index_legacy_log_on_log_id", unique: true
    t.index ["person_id", "created_at"], name: "index_legacy_log_on_person_id_and_created_at"
    t.index ["target_person_id", "created_at"], name: "index_legacy_log_on_target_person_id_and_created_at"
  end

  create_table "log", charset: "utf8mb3", collation: "utf8mb3_unicode_ci", comment: "logs certain actions", force: :cascade do |t|
    t.bigint "user_person_id", comment: "person_id of user making change", unsigned: true
    t.bigint "current_person_id", comment: "person_id of person affected by change (if any)", unsigned: true
    t.timestamp "occurred", default: -> { "current_timestamp()" }, null: false, comment: "time log entry created"
    t.string "event", limit: 500, null: false, comment: "summary of what was done"
    t.index ["current_person_id"], name: "current_person_id"
    t.index ["occurred"], name: "occurred"
    t.index ["user_person_id"], name: "user_person_id"
  end

  create_table "mail_log", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.integer "person_id"
    t.integer "sender_id"
    t.string "from_email", null: false
    t.string "to_email", null: false
    t.string "subject"
    t.string "message_id", null: false
    t.boolean "did_bounce", default: false, null: false
    t.boolean "was_sent", default: false, null: false
    t.integer "broadcast_id"
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.binary "body", size: :long
    t.boolean "did_complain", default: false, null: false
    t.integer "prospective_application_id"
    t.timestamp "delivered_at", comment: "when SES reported the message reached the recipient's mail server"
    t.index ["message_id"], name: "mail_log_message_id_index"
    t.index ["person_id", "created_at"], name: "mail_log_person_id_created_at_index"
    t.index ["prospective_application_id"], name: "mail_log_prospective_application_id_index"
    t.index ["sender_id", "created_at"], name: "mail_log_sender_id_created_at_index"
  end

  create_table "mail_template", charset: "utf8mb4", collation: "utf8mb4_general_ci", comment: "wording of the messages the Clubhouse sends", force: :cascade do |t|
    t.string "tag", limit: 191, null: false, comment: "which message this is the wording for, e.g. welcome_mailer/notify"
    t.string "description", limit: 191, null: false, comment: "what the message is for"
    t.string "subject", limit: 500, comment: "subject line; empty for a shared piece"
    t.text "body", size: :long, null: false, comment: "the HTML part"
    t.text "text_body", size: :long, comment: "the plain text part, where the message has one"
    t.string "seeded_digest", limit: 64, comment: "fingerprint of the text last loaded from db/mail_templates"
    t.bigint "person_create_id", unsigned: true
    t.bigint "person_update_id", unsigned: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tag"], name: "index_mail_template_on_tag", unique: true
  end

  create_table "manual_review", charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.integer "person_id", null: false
    t.datetime "passdate", precision: nil, null: false
  end

  create_table "mentee_status", id: { type: :bigint, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_general_ci", force: :cascade do |t|
    t.integer "mentor_year", null: false, unsigned: true
    t.bigint "person_id", default: 0, null: false, unsigned: true
    t.integer "rank", default: 0, null: false, unsigned: true
    t.text "notes"
    t.index ["mentor_year", "person_id"], name: "mentor_year", unique: true
  end

  create_table "motd", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.text "message", null: false
    t.bigint "person_id", null: false, unsigned: true
    t.boolean "is_alert", default: false, null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.boolean "for_rangers", default: false, null: false
    t.boolean "for_pnvs", default: false, null: false
    t.boolean "for_auditors", default: false, null: false
    t.datetime "expires_at", precision: nil, null: false
    t.string "subject", limit: 191, null: false
    t.index ["expires_at"], name: "motd_expires_at_index"
  end

  create_table "oauth_client", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "client_id", null: false
    t.string "description", null: false
    t.string "secret_digest", null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.string "redirect_uri", default: "", null: false
    t.index ["client_id"], name: "oauth_client_client_id_unique", unique: true
  end

  create_table "oauth_code", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "code_digest", null: false
    t.string "scope", null: false
    t.bigint "oauth_client_id", null: false, unsigned: true
    t.bigint "person_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["oauth_client_id", "code_digest"], name: "index_oauth_code_on_oauth_client_id_and_code_digest", unique: true
    t.index ["person_id"], name: "fk_rails_869bbf9dce"
  end

  create_table "online_course", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "name", default: "", null: false
    t.integer "year", null: false
    t.bigint "position_id", null: false, unsigned: true
    t.string "course_id", default: "", null: false
    t.boolean "active", default: true, null: false
    t.column "course_for", "enum('all','returning','new')", default: "all", null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.index ["position_id", "year", "course_for"], name: "online_course_position_id_year_course_for_unique", unique: true
  end

  create_table "outbound_links", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "url", limit: 1024, null: false
    t.string "url_type", null: false
    t.integer "person_id"
    t.datetime "created_at", null: false
    t.index ["person_id", "created_at"], name: "index_outbound_links_on_person_id_and_created_at"
  end

  create_table "person", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "first_name", limit: 25, null: false
    t.string "mi", limit: 10, default: "", null: false
    t.string "last_name", limit: 25, null: false
    t.string "callsign", limit: 64, null: false
    t.string "street1", limit: 128, default: "", null: false
    t.string "street2", limit: 128, default: "", null: false
    t.string "apt", limit: 10, default: "", null: false
    t.string "city", limit: 50, default: "", null: false
    t.string "state", limit: 128, default: "", null: false
    t.string "zip", limit: 10, default: "", null: false
    t.string "country", limit: 25, default: "", null: false
    t.string "home_phone", limit: 25, default: "", null: false
    t.string "alt_phone", limit: 25, default: "", null: false
    t.string "email"
    t.string "camp_location", limit: 200, default: "", null: false
    t.boolean "on_site", default: false, null: false
    t.boolean "vehicle_blacklisted", default: false, null: false
    t.date "date_verified"
    t.string "password", null: false
    t.datetime "created_at", precision: nil, default: -> { "current_timestamp()" }
    t.boolean "callsign_approved", default: false, null: false
    t.string "shirt_size", limit: 10
    t.column "status", "enum('active','alpha','auditor','bonked','echelon','deceased','dismissed','inactive','inactive extension','past prospective','prospective','resigned','retired','suspended','uberbonked')", null: false
    t.date "status_date"
    t.datetime "updated_at", precision: nil, default: -> { "current_timestamp()" }, null: false, comment: "Most recent modification time."
    t.string "shirt_style", limit: 32
    t.string "gender_custom", limit: 32
    t.string "bpguid", limit: 64
    t.string "sfuid", limit: 64
    t.text "emergency_contact", size: :medium
    t.boolean "vintage", default: false
    t.string "sms_off_playa"
    t.string "sms_on_playa"
    t.boolean "sms_off_playa_stopped", default: false, null: false
    t.boolean "sms_on_playa_stopped", default: false, null: false
    t.boolean "sms_off_playa_verified", default: false, null: false
    t.boolean "sms_on_playa_verified", default: false, null: false
    t.string "sms_off_playa_code", limit: 16
    t.string "sms_on_playa_code", limit: 16
    t.string "callsign_normalized", limit: 128, null: false
    t.string "callsign_soundex", limit: 128, null: false
    t.boolean "behavioral_agreement", default: false, null: false
    t.string "callsign_pronounce", limit: 200
    t.timestamp "logged_in_at"
    t.timestamp "last_seen_at"
    t.bigint "person_photo_id"
    t.text "known_rangers"
    t.text "known_pnvs"
    t.string "lms_id", limit: 191
    t.datetime "reviewed_pi_at", precision: nil
    t.column "pronouns", "enum('','female','male','neutral','custom')", default: "", null: false
    t.string "pronouns_custom", limit: 191, null: false
    t.datetime "pi_reviewed_for_dashboard_at", precision: nil
    t.string "lms_username", limit: 191
    t.boolean "is_bouncing", default: false, null: false
    t.bigint "tshirt_swag_id", unsigned: true
    t.bigint "tshirt_secondary_swag_id", unsigned: true
    t.bigint "long_sleeve_swag_id", unsigned: true
    t.datetime "vanity_changed_at", precision: nil
    t.boolean "used_vanity_change", default: false, null: false
    t.string "employee_id"
    t.column "gender_identity", "enum('cis-female','cis-male','custom','female','fluid','male','','non-binary','queer','trans-female','trans-male','two-spirit')", default: "", null: false
    t.string "preferred_name", default: "", null: false
    t.text "years_seen", size: :long, collation: "utf8mb4_bin"
    t.text "years_as_contributor", size: :long, collation: "utf8mb4_bin"
    t.text "years_as_ranger", size: :long, collation: "utf8mb4_bin"
    t.text "years_combined", size: :long, collation: "utf8mb4_bin"
    t.text "years_of_service", default: "[]", null: false
    t.text "years_of_awards", default: "[]", null: false
    t.text "years_of_signups", default: "[]", null: false
    t.string "sms_number"
    t.boolean "sms_stopped", default: false, null: false
    t.string "sms_code"
    t.boolean "sms_verified", default: false, null: false
    t.datetime "on_boarded_at"
    t.index ["callsign"], name: "callsign", unique: true
    t.index ["callsign_normalized"], name: "person_callsign_normalized_index"
    t.index ["callsign_soundex"], name: "person_callsign_soundex_index"
    t.index ["email"], name: "email", unique: true
    t.index ["lms_id"], name: "person_lms_id_index"
    t.index ["long_sleeve_swag_id"], name: "fk_rails_0b2fe07ac6"
    t.index ["person_photo_id"], name: "fk_rails_d7812cb3e5"
    t.index ["sms_number"], name: "index_person_on_sms_number"
    t.index ["status"], name: "person_status_index"
    t.index ["tshirt_secondary_swag_id"], name: "fk_rails_caca9f7594"
    t.index ["tshirt_swag_id"], name: "fk_rails_d4ce3b4b17"
    t.check_constraint "json_valid(`years_as_contributor`)", name: "years_as_contributor"
    t.check_constraint "json_valid(`years_as_ranger`)", name: "years_as_ranger"
    t.check_constraint "json_valid(`years_combined`)", name: "years_combined"
    t.check_constraint "json_valid(`years_seen`)", name: "years_seen"
  end

  create_table "person_alert", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "alert_id", null: false
    t.boolean "use_sms", default: true, null: false
    t.boolean "use_email", default: true, null: false
    t.timestamp "created_at", default: -> { "current_timestamp()" }, null: false
    t.timestamp "updated_at", default: -> { "current_timestamp() ON UPDATE current_timestamp()" }, null: false
    t.index ["alert_id"], name: "fk_rails_b959b5a80c"
    t.index ["person_id", "alert_id"], name: "person_id", unique: true
  end

  create_table "person_asset", id: { type: :bigint, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "asset_id", null: false
    t.datetime "checked_out", precision: nil, null: false
    t.datetime "checked_in", precision: nil
    t.bigint "attachment_id", unsigned: true
    t.integer "check_out_person_id"
    t.integer "check_in_person_id"
    t.boolean "check_out_forced", default: false, null: false
    t.index ["asset_id"], name: "asset_id"
    t.index ["attachment_id"], name: "fk_rails_120a87780c"
    t.index ["person_id", "checked_out"], name: "person_asset_person_id_checked_out_index"
  end

  create_table "person_award", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "award_id", unsigned: true
    t.text "notes", null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.bigint "team_id", unsigned: true
    t.bigint "position_id", unsigned: true
    t.integer "year", null: false
    t.integer "creator_person_id"
    t.boolean "awards_grants_service_year", default: false, null: false
    t.index ["award_id"], name: "fk_rails_808f800448"
    t.index ["person_id", "award_id"], name: "person_award_person_id_award_id_index"
    t.index ["person_id", "year", "award_id"], name: "person_award_person_id_year_award_id_index"
    t.index ["person_id", "year", "position_id"], name: "person_award_person_id_year_position_id_index"
    t.index ["person_id", "year", "team_id"], name: "person_award_person_id_year_team_id_index"
    t.index ["position_id"], name: "fk_rails_38d43bc726"
    t.index ["team_id"], name: "fk_rails_27f3bc135e"
  end

  create_table "person_banner", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.boolean "is_permanent", default: false, null: false
    t.text "message", null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.bigint "creator_person_id", unsigned: true
    t.bigint "updater_person_id", unsigned: true
    t.index ["person_id", "is_permanent", "created_at"], name: "person_banner_person_id_is_permanent_created_at_index"
  end

  create_table "person_certification", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.integer "recorder_id"
    t.bigint "certification_id", null: false, unsigned: true
    t.date "issued_on"
    t.date "trained_on"
    t.string "card_number"
    t.text "notes"
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.index ["certification_id"], name: "person_certification_certification_id_index"
    t.index ["person_id", "certification_id"], name: "person_certification_person_id_certification_id_index"
  end

  create_table "person_event", primary_key: ["person_id", "year"], charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.integer "year", null: false
    t.boolean "may_request_stickers", default: false, null: false
    t.boolean "org_vehicle_insurance", default: false, null: false
    t.boolean "signed_motorpool_agreement", default: false, null: false
    t.boolean "signed_personal_vehicle_agreement", default: false, null: false
    t.boolean "asset_authorized", default: false, null: false
    t.datetime "timesheet_confirmed_at", precision: nil
    t.boolean "timesheet_confirmed", default: false, null: false
    t.boolean "sandman_affidavit", default: false, null: false
    t.boolean "signed_nda", default: false, null: false
    t.datetime "ticketing_started_at", precision: nil
    t.datetime "ticketing_last_visited_at", precision: nil
    t.datetime "ticketing_finished_at", precision: nil
    t.datetime "pii_started_at", precision: nil
    t.datetime "pii_finished_at", precision: nil
    t.datetime "lms_enrolled_at", precision: nil
    t.boolean "mvr_eligible", default: false, null: false
    t.boolean "ignore_mvr", default: false, null: false
    t.boolean "ignore_pvr", default: false, null: false
    t.index ["year", "mvr_eligible"], name: "person_event_year_mvr_eligible_index"
  end

  create_table "person_favorite", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.string "path", limit: 191, null: false
    t.datetime "created_at", null: false
    t.index ["person_id", "path"], name: "index_person_favorite_on_person_id_and_path", unique: true
  end

  create_table "person_fka", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.datetime "created_at", precision: nil
    t.string "fka", null: false
    t.string "fka_normalized", null: false
    t.string "fka_soundex", null: false
    t.boolean "is_irrelevant", default: false, null: false
    t.index ["person_id", "fka"], name: "person_fka_person_id_fka_index"
    t.index ["person_id", "fka_normalized"], name: "person_fka_person_id_fka_normalized_index"
    t.index ["person_id", "fka_soundex"], name: "person_fka_person_id_fka_soundex_index"
  end

  create_table "person_intake", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.integer "year", null: false
    t.integer "mentor_rank"
    t.integer "rrn_rank"
    t.integer "vc_rank"
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.integer "personnel_rank"
    t.index ["person_id", "year"], name: "person_intake_person_id_year_unique", unique: true
    t.index ["year"], name: "index_person_intake_on_year"
  end

  create_table "person_intake_note", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "person_source_id", null: false
    t.integer "year", null: false
    t.boolean "is_log", default: false, null: false
    t.column "type", "enum('mentor','rrn','personnel','vc')", null: false
    t.text "note", null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.index ["person_id", "year"], name: "person_intake_note_person_id_year_index"
    t.index ["year", "is_log"], name: "index_person_intake_note_on_year_and_is_log"
  end

  create_table "person_language", id: :integer, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.string "language_name", limit: 32, null: false
    t.string "proficiency", default: "unknown", null: false
    t.string "language_custom", limit: 32
    t.index ["person_id", "language_name", "language_custom"], name: "person_language_person_id_language_name_language_custom_index"
    t.index ["person_id"], name: "person_id"
  end

  create_table "person_mentor", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "mentor_id", unsigned: true
    t.integer "mentor_year", null: false, unsigned: true
    t.column "status", "enum('pass','bonk','self-bonk','pending','abstain','not-completed')"
    t.text "notes", size: :medium
    t.bigint "position_id", default: 1, null: false, unsigned: true
    t.bigint "timesheet_id", unsigned: true
    t.virtual "mentor_key", type: :bigint, unsigned: true, as: "ifnull(`mentor_id`,0)", stored: true
    t.index ["mentor_id", "position_id"], name: "index_person_mentor_on_mentor_id_and_position_id"
    t.index ["mentor_year", "status"], name: "index_person_mentor_on_mentor_year_and_status"
    t.index ["person_id", "mentor_id", "mentor_year", "position_id", "timesheet_id"], name: "person_id", unique: true
    t.index ["position_id"], name: "fk_rails_a07f9146ba"
    t.index ["timesheet_id", "mentor_key"], name: "index_person_mentor_on_timesheet_id_and_mentor_key", unique: true
  end

  create_table "person_mentoring_note", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false, unsigned: true
    t.bigint "written_by_id", null: false, unsigned: true
    t.text "notes", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["person_id"], name: "index_person_mentoring_note_on_person_id"
    t.index ["written_by_id"], name: "index_person_mentoring_note_on_written_by_id"
  end

  create_table "person_message", id: :integer, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.integer "person_id", null: false
    t.integer "creator_person_id", null: false
    t.datetime "created_at", precision: nil, default: -> { "current_timestamp()" }, null: false
    t.string "subject", default: "", null: false
    t.text "body", size: :medium, null: false
    t.text "body_text", size: :medium, default: "", null: false
    t.string "message_from", default: "", null: false
    t.datetime "expires_at", precision: nil
    t.integer "broadcast_id"
    t.integer "reply_to_id"
    t.integer "sender_person_id"
    t.integer "sender_team_id"
    t.integer "recipient_team_id"
    t.integer "creator_position_id"
    t.column "message_type", "enum('normal','contact','mentor')", default: "normal", null: false
    t.column "sender_type", "enum('person','team','rbs','other')", default: "person"
    t.boolean "group", default: false, null: false
    t.index ["person_id", "created_at"], name: "person_message_person_id_created_at_index"
    t.index ["reply_to_id"], name: "index_person_message_on_reply_to_id"
    t.index ["sender_person_id", "created_at"], name: "person_message_sender_person_id_created_at_index"
    t.index ["sender_person_id", "reply_to_id", "created_at"], name: "person_message_sender_person_id_reply_to_id_created_at_index"
    t.index ["subject", "body_text"], name: "index_person_message_on_subject_and_body_text", type: :fulltext
  end

  create_table "person_message_member", id: :integer, charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.integer "person_message_id", null: false
    t.bigint "person_id", null: false
    t.boolean "archived", default: false, null: false
    t.datetime "created_at", precision: nil, null: false
    t.integer "last_read_message_id"
    t.integer "team_id"
    t.index ["person_id", "archived"], name: "index_person_message_member_on_person_id_and_archived"
    t.index ["person_message_id", "person_id"], name: "index_person_message_member_on_person_message_id_and_person_id", unique: true
    t.index ["team_id"], name: "index_person_message_member_on_team_id"
  end

  create_table "person_motd", primary_key: ["person_id", "motd_id"], charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "motd_id", null: false, unsigned: true
    t.datetime "read_at", precision: nil, null: false
    t.index ["motd_id"], name: "fk_rails_e0ba5f229e"
  end

  create_table "person_on_site", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "creator_person_id"
    t.column "action", "enum('on-site','off-site')", null: false
    t.datetime "created_at", null: false
    t.index ["creator_person_id"], name: "index_person_on_site_on_creator_person_id"
    t.index ["person_id", "created_at"], name: "index_person_on_site_on_person_id_and_created_at"
  end

  create_table "person_online_course", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.datetime "completed_at", precision: nil
    t.string "type", limit: 191, default: "", null: false
    t.timestamp "created_at", default: -> { "current_timestamp()" }, null: false
    t.bigint "position_id", default: 0, null: false, unsigned: true
    t.integer "online_course_id", default: 0, null: false
    t.integer "year", default: 0, null: false
    t.datetime "enrolled_at", precision: nil
    t.index ["person_id", "completed_at"], name: "person_online_training_person_id_completed_at_index"
    t.index ["person_id", "position_id", "year"], name: "person_online_course_person_id_position_id_year_unique", unique: true
    t.index ["position_id"], name: "fk_rails_f2050905cc"
  end

  create_table "person_page_visit", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.string "path", limit: 191, null: false
    t.datetime "visited_at", null: false
    t.index ["person_id", "path"], name: "index_person_page_visit_on_person_id_and_path", unique: true
  end

  create_table "person_passkey", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "added_by_person_id"
    t.string "external_id", limit: 1364, null: false, collation: "ascii_bin"
    t.text "public_key", null: false
    t.bigint "sign_count", default: 0, null: false, unsigned: true
    t.string "nickname", limit: 50, null: false
    t.string "aaguid", limit: 36
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["added_by_person_id"], name: "index_person_passkey_on_added_by_person_id"
    t.index ["external_id"], name: "index_person_passkey_on_external_id", unique: true
    t.index ["person_id"], name: "index_person_passkey_on_person_id"
  end

  create_table "person_photo", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.column "status", "enum('approved','archived','rejected','submitted','uploaded')", null: false
    t.string "image_filename", limit: 191, null: false
    t.integer "width", default: 0, null: false
    t.integer "height", default: 0, null: false
    t.string "orig_filename", limit: 191, null: false
    t.integer "orig_width", default: 0, null: false
    t.integer "orig_height", default: 0, null: false
    t.text "reject_message", size: :long
    t.datetime "reviewed_at", precision: nil
    t.bigint "review_person_id"
    t.datetime "uploaded_at", precision: nil
    t.bigint "upload_person_id"
    t.datetime "edited_at", precision: nil
    t.bigint "edit_person_id"
    t.text "analysis_info", size: :long
    t.column "analysis_status", "enum('success','failed','none')", default: "none", null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.string "profile_filename"
    t.integer "profile_width", default: 0, null: false
    t.integer "profile_height", default: 0, null: false
    t.text "reject_reasons", size: :long, default: "{}", collation: "utf8mb4_bin"
    t.text "cropping", size: :long, default: "{}", null: false, collation: "utf8mb4_bin"
    t.index ["person_id"], name: "person_photo_person_id_index"
    t.check_constraint "json_valid(`cropping`)", name: "cropping"
    t.check_constraint "json_valid(`reject_reasons`)", name: "reject_reasons_json"
  end

  create_table "person_pod", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.bigint "pod_id", null: false, unsigned: true
    t.bigint "person_id", null: false
    t.boolean "is_lead", default: false, null: false
    t.datetime "joined_at", precision: nil, null: false
    t.datetime "left_at", precision: nil
    t.datetime "removed_at", precision: nil
    t.integer "sort_index", default: 0, null: false
    t.bigint "timesheet_id", unsigned: true
    t.index ["person_id"], name: "fk_rails_2d2baf515b"
    t.index ["pod_id", "person_id"], name: "person_pod_pod_id_person_id_index"
    t.index ["timesheet_id"], name: "person_pod_timesheet_id_index"
  end

  create_table "person_pog", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.bigint "person_id", null: false
    t.integer "issued_by_id", null: false
    t.bigint "timesheet_id", unsigned: true
    t.string "pog", null: false
    t.string "status", null: false
    t.text "notes", null: false
    t.datetime "issued_at", precision: nil, null: false
    t.index ["person_id", "pog", "created_at"], name: "person_pog_person_id_pog_created_at_index"
    t.index ["timesheet_id"], name: "fk_rails_979901a9e1"
  end

  create_table "person_position", primary_key: ["person_id", "position_id"], charset: "utf8mb3", collation: "utf8mb3_unicode_ci", comment: "links person to position", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "position_id", null: false, unsigned: true
    t.index ["position_id"], name: "index_person_position_on_position_id"
  end

  create_table "person_position_log", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.integer "position_id", null: false
    t.integer "person_id", null: false
    t.date "joined_on", null: false
    t.date "left_on"
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.index ["person_id", "left_on"], name: "index_person_position_log_on_person_id_and_left_on"
    t.index ["position_id", "left_on"], name: "index_person_position_log_on_position_id_and_left_on"
  end

  create_table "person_role", primary_key: ["person_id", "role_id"], charset: "utf8mb4", collation: "utf8mb4_unicode_ci", comment: "links person to role", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "role_id", null: false, unsigned: true
    t.index ["role_id"], name: "fk_rails_acfe160ac8"
  end

  create_table "person_slot", id: { type: :bigint, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "slot_id", null: false, unsigned: true
    t.datetime "created_at", precision: nil, default: -> { "current_timestamp()" }, null: false
    t.index ["person_id"], name: "person_id"
    t.index ["slot_id", "person_id"], name: "person_slot_slot_id_person_id", unique: true
  end

  create_table "person_status", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "person_source_id"
    t.string "new_status", limit: 191, null: false
    t.string "old_status", limit: 191, null: false
    t.string "reason", limit: 191
    t.datetime "created_at", precision: nil, default: -> { "current_timestamp()" }, null: false
    t.index ["new_status", "created_at"], name: "index_person_status_on_new_status_and_created_at"
    t.index ["person_id"], name: "person_status_person_id_index"
    t.index ["person_source_id"], name: "person_status_person_source_id_index"
  end

  create_table "person_swag", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "swag_id", null: false, unsigned: true
    t.integer "year_issued"
    t.text "notes", null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.index ["person_id", "swag_id"], name: "person_swag_person_id_swag_id_index"
    t.index ["swag_id"], name: "fk_rails_352f8e2940"
  end

  create_table "person_team", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "team_id", null: false, unsigned: true
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.index ["person_id", "team_id"], name: "person_team_person_id_team_id_unique", unique: true
    t.index ["team_id", "person_id"], name: "index_person_team_on_team_id_and_person_id"
  end

  create_table "person_team_log", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.integer "team_id", null: false
    t.integer "person_id", null: false
    t.date "joined_on", null: false
    t.date "left_on"
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.index ["person_id", "left_on"], name: "index_person_team_log_on_person_id_and_left_on"
    t.index ["team_id", "left_on"], name: "index_person_team_log_on_team_id_and_left_on"
  end

  create_table "pod", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.column "type", "enum('alpha','mentor','mitten','shift')", null: false
    t.datetime "formed_at", precision: nil, null: false
    t.datetime "disbanded_at", precision: nil
    t.bigint "slot_id", unsigned: true
    t.bigint "mentor_pod_id", unsigned: true
    t.integer "person_count", default: 0, null: false
    t.integer "sort_index", default: 0, null: false
    t.string "location"
    t.column "transport", "enum('foot','bicycle','vehicle')", default: "foot", null: false
    t.index ["formed_at"], name: "pod_formed_at_index"
    t.index ["mentor_pod_id"], name: "fk_rails_43e94f5e16"
    t.index ["slot_id", "formed_at"], name: "pod_slot_id_formed_at_index"
  end

  create_table "position", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "title", limit: 40, null: false
    t.boolean "new_user_eligible", default: false, null: false
    t.boolean "all_rangers", default: false, null: false
    t.boolean "count_hours", default: true, null: false
    t.integer "min", default: 1, null: false, comment: "Min suggested Rangers per slot"
    t.integer "max", comment: "Max suggested Rangers per slot"
    t.boolean "on_sl_report"
    t.boolean "on_trainer_report", default: false, null: false
    t.string "short_title", limit: 6
    t.string "type", limit: 32
    t.bigint "training_position_id", unsigned: true
    t.string "contact_email", limit: 200
    t.boolean "prevent_multiple_enrollments", default: false, null: false
    t.boolean "active", default: true, null: false
    t.boolean "alert_when_empty", default: false, null: false
    t.bigint "team_id", unsigned: true
    t.boolean "require_training_for_roles", default: false, null: false
    t.column "team_category", "enum('public','all_members','optional')", default: "public", null: false
    t.boolean "alert_when_becomes_empty", default: false, null: false
    t.boolean "alert_when_no_trainers", default: false, null: false
    t.string "paycode"
    t.string "resource_tag"
    t.boolean "deselect_on_team_join", default: false, null: false
    t.boolean "no_payroll_hours_adjustment", default: false, null: false
    t.boolean "no_training_required", default: false, null: false
    t.boolean "auto_sign_out", default: false, null: false
    t.float "sign_out_hour_cap", limit: 53, default: 0.0, null: false
    t.boolean "mvr_eligible", default: false, null: false
    t.boolean "pvr_eligible", default: false, null: false
    t.bigint "parent_position_id", unsigned: true
    t.boolean "not_timesheet_eligible", default: false, null: false
    t.boolean "cruise_direction", default: false, null: false
    t.boolean "mvr_signup_eligible", default: false, null: false
    t.boolean "awards_eligible", default: false, null: false
    t.boolean "awards_auto_grant", default: false, null: false
    t.boolean "awards_grants_service_year", default: false, null: false
    t.boolean "allow_echelon", default: false, null: false
    t.boolean "has_online_course", default: false, null: false
    t.boolean "require_signin_for_roles", default: false, null: false
    t.boolean "is_checkin_time_restricted", default: false, null: false
    t.boolean "has_art_mentoring", default: false, null: false
    t.boolean "is_art_mentor", default: false, null: false
    t.boolean "is_art_mentee", default: false, null: false
    t.text "ranger_scheduling_header", size: :medium
    t.text "applicant_scheduling_header", size: :medium
    t.index ["awards_auto_grant"], name: "position_awards_auto_grant_index"
    t.index ["cruise_direction"], name: "position_cruise_direction_index"
    t.index ["mvr_eligible"], name: "position_mvr_eligible_index"
    t.index ["parent_position_id"], name: "position_parent_position_id_index"
    t.index ["pvr_eligible"], name: "position_pvr_eligible_index"
    t.index ["team_id"], name: "fk_rails_a7a42c945b"
    t.index ["training_position_id"], name: "fk_rails_e2f2a7f980"
  end

  create_table "position_credit", id: :integer, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.bigint "position_id", null: false, unsigned: true
    t.datetime "start_time", precision: nil, null: false
    t.datetime "end_time", precision: nil, null: false
    t.decimal "credits_per_hour", precision: 4, scale: 2, null: false
    t.string "description", limit: 25, null: false
    t.virtual "start_year", type: :integer, as: "year(`start_time`)", stored: true
    t.virtual "end_year", type: :integer, as: "year(`end_time`)", stored: true
    t.virtual "start_timestamp", type: :bigint, as: "unix_timestamp(`start_time`)", stored: true
    t.virtual "end_timestamp", type: :bigint, as: "unix_timestamp(`end_time`)", stored: true
    t.index ["position_id", "start_time"], name: "position_credit_position_id_start_time_index"
    t.index ["start_year", "end_year"], name: "position_credit_start_year_end_year_index"
    t.index ["start_year", "position_id"], name: "position_credit_start_year_position_id_index"
  end

  create_table "position_lineup", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "description", null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
  end

  create_table "position_lineup_member", primary_key: "position_id", id: { type: :bigint, unsigned: true, default: nil }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "position_lineup_id", null: false, unsigned: true
    t.datetime "created_at", precision: nil, null: false
    t.index ["position_lineup_id"], name: "fk_rails_475aeb185b"
  end

  create_table "position_role", primary_key: ["position_id", "role_id"], charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "position_id", null: false, unsigned: true
    t.bigint "role_id", null: false, unsigned: true
    t.index ["role_id"], name: "fk_rails_877d125c67"
  end

  create_table "prospective_application", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "status", default: "pending", null: false
    t.text "events_attended", default: "", null: false
    t.string "salesforce_name", default: "", null: false
    t.string "salesforce_id", default: "", null: false
    t.string "sfuid", default: "", null: false
    t.string "first_name", default: "", null: false
    t.string "last_name", default: "", null: false
    t.string "street", default: "", null: false
    t.string "city", default: "", null: false
    t.string "state", default: "", null: false
    t.string "country", default: "", null: false
    t.string "postal_code", default: "", null: false
    t.string "phone", default: "", null: false
    t.integer "year", null: false
    t.string "email", null: false
    t.string "bpguid", null: false
    t.bigint "person_id"
    t.text "why_volunteer", default: "", null: false
    t.string "why_volunteer_review", default: "unreviewed", null: false
    t.integer "review_person_id"
    t.datetime "reviewed_at", precision: nil
    t.string "known_rangers", default: "", null: false
    t.string "known_applicants", default: "", null: false
    t.boolean "is_over_18", default: false, null: false
    t.text "handles", default: "", null: false
    t.string "approved_handle", default: "", null: false
    t.text "rejected_handles"
    t.text "regional_experience", default: "", null: false
    t.string "regional_callsign", default: "", null: false
    t.string "experience", default: "none", null: false
    t.string "emergency_contact", default: "", null: false
    t.integer "assigned_person_id"
    t.integer "updated_by_person_id"
    t.datetime "updated_by_person_at", precision: nil
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.text "problem_handles"
    t.index ["created_at"], name: "index_prospective_application_on_created_at"
    t.index ["person_id"], name: "fk_rails_21577f48b2"
    t.index ["year", "status"], name: "prospective_application_year_status_index"
  end

  create_table "prospective_application_log", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "prospective_application_id", null: false, unsigned: true
    t.integer "person_id"
    t.text "data"
    t.string "action", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["prospective_application_id"], name: "prospective_application_log_prospective_application_id_index"
  end

  create_table "prospective_application_note", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "type", null: false
    t.bigint "prospective_application_id", null: false, unsigned: true
    t.integer "person_id"
    t.text "note", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["prospective_application_id"], name: "prospective_application_note_prospective_application_id_index"
  end

  create_table "provision", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.integer "source_year", null: false
    t.string "type", null: false
    t.string "status", default: "available", null: false
    t.date "expires_on", null: false
    t.text "comments", size: :long
    t.boolean "is_allocated", default: false, null: false
    t.integer "item_count"
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.integer "consumed_year"
    t.boolean "pre_event_meals", default: false, null: false
    t.boolean "event_week_meals", default: false, null: false
    t.boolean "post_event_meals", default: false, null: false
    t.index ["person_id"], name: "fk_rails_ac39c5a71c"
  end

  create_table "radio_eligible", primary_key: ["person_id", "year"], charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.integer "person_id", null: false
    t.integer "year", null: false
    t.integer "max_radios", null: false
  end

  create_table "radio_log", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.integer "channel_id", null: false
    t.string "radio_id", limit: 12, null: false
    t.integer "person_id"
    t.string "callsign", limit: 100
    t.string "caller_type", limit: 100, null: false
    t.integer "position_id"
    t.datetime "on_duty", precision: nil
    t.datetime "started_at", precision: 3, null: false
    t.datetime "ended_at", precision: 3
    t.integer "pod_id"
    t.text "partners"
    t.index ["radio_id", "ended_at"], name: "radio_id_3"
    t.index ["radio_id", "started_at"], name: "radio_id_2"
  end

  create_table "request_log", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.integer "person_id"
    t.string "url", null: false
    t.string "ips", null: false
    t.integer "status", null: false
    t.string "method", null: false
    t.integer "response_size", null: false
    t.float "completion_time", limit: 53, null: false
    t.timestamp "created_at", default: -> { "current_timestamp()" }, null: false
    t.text "request_payload", size: :long
    t.text "response_payload", size: :long
    t.index ["created_at"], name: "request_log_created_at_index"
    t.index ["person_id"], name: "request_log_person_id_index"
    t.index ["status", "created_at"], name: "request_log_status_created_at_index"
  end

  create_table "role", id: { type: :bigint, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", comment: "authorization roles", force: :cascade do |t|
    t.string "title", null: false
    t.boolean "new_user_eligible", default: false, null: false
  end

  create_table "sessions", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "session_id"
    t.string "ip_address"
    t.string "user_agent"
    t.bigint "person_id"
    t.text "data", size: :medium
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_sessions_on_person_id"
    t.index ["session_id"], name: "index_sessions_on_session_id", unique: true
  end

  create_table "setting", id: { type: :integer, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "name", limit: 128, null: false
    t.text "value"
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.index ["name"], name: "setting_name_unique", unique: true
  end

  create_table "shift_coverage_group", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "slug", null: false
    t.string "title", null: false
    t.text "base_position_ids", size: :long, null: false, collation: "utf8mb4_bin"
    t.integer "sort_index", null: false
    t.index ["slug"], name: "index_shift_coverage_group_on_slug", unique: true
    t.check_constraint "json_valid(`base_position_ids`)", name: "base_position_ids"
  end

  create_table "shift_coverage_position", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "title", null: false
    t.text "position_ids", size: :long, null: false, collation: "utf8mb4_bin"
    t.boolean "count_only", default: false, null: false
    t.bigint "shift_coverage_group_id", null: false
    t.integer "sort_index", null: false
    t.index ["shift_coverage_group_id"], name: "index_shift_coverage_position_on_shift_coverage_group_id"
    t.check_constraint "json_valid(`position_ids`)", name: "position_ids"
  end

  create_table "slot", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", comment: "schedule slot", force: :cascade do |t|
    t.datetime "begins", precision: nil, null: false
    t.datetime "ends", precision: nil, null: false
    t.bigint "position_id", null: false, unsigned: true
    t.string "description", limit: 40, comment: "(\"day\", \"night\", etc.)"
    t.bigint "signed_up", default: 0, null: false, unsigned: true
    t.bigint "max", default: 0, null: false, comment: "if trainee slot, this is * slot[trainer_slot_id].signed_up", unsigned: true
    t.string "url", limit: 512
    t.bigint "trainer_slot_id", comment: "if trainee slot, slot.id for corresponding trainer slot, else null", unsigned: true
    t.bigint "trainee_slot_id", comment: "if trainer slot, slot.id for corresponding trainee slot, else null", unsigned: true
    t.bigint "training_id", default: 0, null: false, unsigned: true
    t.integer "min", default: 1, null: false
    t.boolean "active", default: false, null: false
    t.string "timezone", default: "America/Los_Angeles", null: false
    t.string "timezone_abbr", null: false
    t.integer "begins_year", default: 0, null: false
    t.integer "duration", default: 0, null: false
    t.integer "begins_time", default: 0, null: false
    t.integer "ends_time", default: 0, null: false
    t.bigint "parent_signup_slot_id", unsigned: true
    t.boolean "did_notify", default: false, null: false
    t.index ["begins"], name: "begins"
    t.index ["begins_year", "position_id"], name: "slot_begins_year_position_id_index"
    t.index ["parent_signup_slot_id"], name: "slot_parent_signup_slot_id_index"
    t.index ["position_id"], name: "position_id"
    t.index ["trainee_slot_id"], name: "fk_rails_f9d2ce86a9"
    t.index ["trainer_slot_id"], name: "fk_rails_65977306a3"
  end

  create_table "solid_cable_messages", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.binary "channel", limit: 1024, null: false
    t.binary "payload", size: :long, null: false
    t.datetime "created_at", null: false
    t.bigint "channel_hash", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.binary "key", limit: 1024, null: false
    t.binary "value", size: :long, null: false
    t.datetime "created_at", null: false
    t.bigint "key_hash", null: false
    t.integer "byte_size", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_batch_executions", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.string "description"
    t.text "on_finish"
    t.text "on_success"
    t.text "on_failure"
    t.text "metadata"
    t.integer "total_jobs", default: 0, null: false
    t.integer "completed_jobs", default: 0, null: false
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "enqueued_at"
    t.datetime "finished_at"
    t.datetime "failed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "batch_id"
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "survey", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.integer "year", null: false
    t.column "type", "enum('trainer','training','alpha','mentor-for-mentees','mentees-for-mentor')", null: false
    t.bigint "position_id", unsigned: true
    t.string "title", limit: 191, null: false
    t.text "prologue", null: false
    t.text "epilogue", null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.boolean "active", default: true, null: false
    t.bigint "mentoring_position_id", unsigned: true
    t.index ["mentoring_position_id"], name: "fk_rails_b502626f61"
    t.index ["position_id"], name: "fk_rails_4cd8358882"
  end

  create_table "survey_answer", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.string "callsign", limit: 191
    t.bigint "survey_id", null: false, unsigned: true
    t.bigint "survey_question_id", null: false, unsigned: true
    t.bigint "survey_group_id", null: false, unsigned: true
    t.text "response", null: false
    t.bigint "slot_id", unsigned: true
    t.bigint "trainer_id"
    t.boolean "can_share_name", default: true, null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.index ["person_id"], name: "survey_answer_person_id_index"
    t.index ["slot_id"], name: "survey_answer_slot_id_index"
    t.index ["survey_group_id"], name: "survey_answer_survey_group_id_index"
    t.index ["survey_id"], name: "survey_answer_survey_id_index"
    t.index ["survey_question_id"], name: "survey_answer_survey_question_id_index"
    t.index ["trainer_id"], name: "survey_answer_trainer_id_index"
  end

  create_table "survey_group", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "survey_id", null: false, unsigned: true
    t.integer "sort_index", default: 1, null: false
    t.string "title", limit: 191, null: false
    t.text "description", null: false
    t.boolean "is_trainer_group", default: false, null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.string "type", limit: 191, default: "normal", null: false
    t.string "report_title", limit: 191, null: false
    t.index ["survey_id", "sort_index"], name: "survey_group_survey_id_sort_index_index"
  end

  create_table "survey_question", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "survey_id", null: false, unsigned: true
    t.bigint "survey_group_id", null: false, unsigned: true
    t.integer "sort_index", default: 1, null: false
    t.boolean "is_required", default: false, null: false
    t.text "options", null: false
    t.text "description", null: false
    t.column "type", "enum('rating','options','text')", null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.boolean "summarize_rating", default: false, null: false
    t.index ["survey_group_id", "sort_index"], name: "survey_question_survey_group_id_sort_index_index"
    t.index ["survey_id"], name: "survey_question_survey_id_index"
  end

  create_table "swag", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.string "title", null: false
    t.string "type", null: false
    t.boolean "active", null: false
    t.string "shirt_type"
    t.text "description"
  end

  create_table "team", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "title", null: false
    t.string "type", default: "team", null: false
    t.boolean "active", default: true, null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.boolean "mvr_eligible", default: false, null: false
    t.boolean "pvr_eligible", default: false, null: false
    t.string "email"
    t.text "description", size: :long
    t.boolean "awards_eligible", default: false, null: false
    t.boolean "awards_auto_grant", default: false, null: false
    t.boolean "awards_grants_service_year", default: false, null: false
    t.string "resource_tag"
    t.boolean "include_in_directory", default: false, null: false
    t.index ["awards_auto_grant"], name: "team_awards_auto_grant_index"
    t.index ["mvr_eligible"], name: "team_mvr_eligible_index"
    t.index ["pvr_eligible"], name: "team_pvr_eligible_index"
  end

  create_table "team_manager", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "team_id", null: false, unsigned: true
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.index ["person_id", "team_id"], name: "index_team_manager_on_person_id_and_team_id", unique: true
    t.index ["team_id"], name: "fk_rails_ab674ecf4e"
  end

  create_table "team_role", primary_key: ["team_id", "role_id"], charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "team_id", null: false, unsigned: true
    t.bigint "role_id", null: false, unsigned: true
    t.index ["role_id"], name: "fk_rails_d5f672b9f3"
  end

  create_table "timesheet", id: { type: :bigint, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_unicode_ci", force: :cascade do |t|
    t.bigint "position_id", null: false, unsigned: true
    t.bigint "person_id", null: false
    t.datetime "on_duty", precision: nil, null: false, comment: "date/time that person signed onto duty"
    t.datetime "off_duty", precision: nil, comment: "date/time that person signed off of duty"
    t.datetime "verified_at", precision: nil
    t.bigint "verified_person_id"
    t.column "review_status", "enum('approved','rejected','pending','unverified','verified')", default: "unverified"
    t.bigint "reviewer_person_id"
    t.datetime "reviewed_at", precision: nil
    t.bigint "slot_id", unsigned: true
    t.boolean "is_echelon", default: false, null: false
    t.boolean "suppress_duration_warning", default: false, null: false
    t.boolean "was_signin_forced", default: false, null: false
    t.bigint "desired_position_id", unsigned: true
    t.datetime "desired_on_duty", precision: nil
    t.datetime "desired_off_duty", precision: nil
    t.text "signin_force_reason"
    t.index ["desired_position_id"], name: "fk_rails_17bf59465e"
    t.index ["on_duty", "was_signin_forced"], name: "timesheet_on_duty_was_signin_forced_index"
    t.index ["person_id", "on_duty"], name: "timesheet_person_id_on_duty_index"
    t.index ["person_id", "position_id"], name: "timesheet_person_id_position_id_index"
    t.index ["position_id", "on_duty"], name: "timesheet_position_id_on_duty_index"
    t.index ["review_status"], name: "verified"
    t.index ["slot_id"], name: "timesheet_slot_id"
  end

  create_table "timesheet_log", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.integer "create_person_id"
    t.bigint "timesheet_id"
    t.column "action", "enum('unconfirmed','confirmed','signon','signoff','created','update','delete','review','verify','unverified','delete-mistake')", null: false
    t.text "message", size: :medium
    t.datetime "created_at", precision: nil, null: false
    t.integer "year", default: 0, null: false
    t.text "data", size: :long
    t.index ["person_id", "action"], name: "person_id"
  end

  create_table "timesheet_missing", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "create_person_id", null: false
    t.bigint "position_id", null: false
    t.datetime "on_duty", precision: nil, null: false
    t.datetime "off_duty", precision: nil, null: false
    t.string "partner", null: false
    t.column "review_status", "enum('approved','rejected','pending')", default: "pending"
    t.bigint "reviewer_person_id"
    t.datetime "reviewed_at", precision: nil
    t.datetime "created_at", precision: nil, default: -> { "current_timestamp()" }
    t.index ["person_id", "review_status"], name: "person_id"
  end

  create_table "timesheet_missing_note", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "timesheet_missing_id", null: false
    t.column "type", "enum('user','hq-worker','wrangler','admin')", default: "user", null: false
    t.text "note", null: false
    t.integer "create_person_id"
    t.datetime "created_at", precision: nil, null: false
    t.index ["timesheet_missing_id"], name: "fk_rails_d33e1dccfc"
  end

  create_table "timesheet_note", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "timesheet_id", null: false, unsigned: true
    t.text "note", null: false
    t.integer "create_person_id"
    t.column "type", "enum('user','hq-worker','wrangler','admin')", default: "user", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["timesheet_id"], name: "fk_rails_27e66aa061"
  end

  create_table "trainee_note", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.integer "person_source_id"
    t.bigint "slot_id", null: false, unsigned: true
    t.text "note", null: false
    t.boolean "is_log", default: false, null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.index ["person_id", "slot_id"], name: "trainee_note_person_id_slot_id_index"
    t.index ["slot_id"], name: "index_trainee_note_on_slot_id"
  end

  create_table "trainee_status", id: { type: :bigint, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_general_ci", force: :cascade do |t|
    t.bigint "slot_id", default: 0, null: false, unsigned: true
    t.bigint "person_id", default: 0, null: false
    t.text "notes"
    t.integer "rank", default: 0, unsigned: true
    t.boolean "feedback_delivered", default: false, null: false
    t.string "status", limit: 16, default: "pending", null: false
    t.index ["person_id"], name: "person_id"
    t.index ["slot_id"], name: "slot_id"
  end

  create_table "trainer_status", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id", null: false
    t.bigint "trainer_slot_id", null: false, unsigned: true
    t.bigint "slot_id", null: false, unsigned: true
    t.column "status", "enum('attended','no-show','pending')", default: "attended", null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.boolean "is_lead", default: false, null: false
    t.index ["person_id", "slot_id"], name: "person_id_and_slot_id", unique: true
    t.index ["slot_id"], name: "index_trainer_status_on_slot_id"
    t.index ["trainer_slot_id"], name: "fk_rails_0e396e1fac"
  end

  create_table "vehicle", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "person_id"
    t.column "type", "enum('personal','fleet')", null: false
    t.integer "event_year", null: false
    t.column "status", "enum('pending','approved','rejected')", default: "pending", null: false
    t.string "vehicle_year", limit: 191, default: "", null: false
    t.string "vehicle_class", limit: 191, default: "", null: false
    t.string "vehicle_make", limit: 191, default: "", null: false
    t.string "vehicle_model", limit: 191, default: "", null: false
    t.string "vehicle_color", limit: 191, default: "", null: false
    t.string "vehicle_type", limit: 191, default: "", null: false
    t.string "license_state", limit: 191, default: "", null: false
    t.string "license_number", limit: 191, default: "", null: false
    t.string "rental_number", limit: 191, default: "", null: false
    t.column "driving_sticker", "enum('none','prepost','staff','other')", default: "none", null: false
    t.string "sticker_number", limit: 191, default: "", null: false
    t.column "fuel_chit", "enum('event','single-use','none')", default: "none", null: false
    t.column "ranger_logo", "enum('permanent-new','permanent-existing','event','none')", default: "none", null: false
    t.column "amber_light", "enum('department','already-has','none')", default: "none", null: false
    t.text "team_assignment", null: false
    t.text "notes", null: false
    t.text "response", null: false
    t.text "request_comment", null: false
    t.timestamp "created_at"
    t.timestamp "updated_at"
    t.index ["event_year"], name: "vehicle_event_year_index"
    t.index ["person_id"], name: "vehicle_person_id_index"
  end

  add_foreign_key "access_document", "person"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "bmid", "person"
  add_foreign_key "bmid_title", "position"
  add_foreign_key "broadcast", "alert"
  add_foreign_key "broadcast_message", "broadcast"
  add_foreign_key "email_history", "person"
  add_foreign_key "oauth_code", "oauth_client"
  add_foreign_key "oauth_code", "person"
  add_foreign_key "online_course", "position"
  add_foreign_key "person", "person_photo", on_delete: :nullify
  add_foreign_key "person", "swag", column: "long_sleeve_swag_id", on_delete: :nullify
  add_foreign_key "person", "swag", column: "tshirt_secondary_swag_id", on_delete: :nullify
  add_foreign_key "person", "swag", column: "tshirt_swag_id", on_delete: :nullify
  add_foreign_key "person_alert", "alert"
  add_foreign_key "person_alert", "person"
  add_foreign_key "person_asset", "asset"
  add_foreign_key "person_asset", "asset_attachment", column: "attachment_id", on_delete: :nullify
  add_foreign_key "person_asset", "person"
  add_foreign_key "person_award", "award"
  add_foreign_key "person_award", "person"
  add_foreign_key "person_award", "position"
  add_foreign_key "person_award", "team"
  add_foreign_key "person_banner", "person"
  add_foreign_key "person_certification", "certification"
  add_foreign_key "person_certification", "person"
  add_foreign_key "person_event", "person"
  add_foreign_key "person_favorite", "person"
  add_foreign_key "person_fka", "person"
  add_foreign_key "person_intake", "person"
  add_foreign_key "person_intake_note", "person"
  add_foreign_key "person_language", "person"
  add_foreign_key "person_mentor", "person"
  add_foreign_key "person_mentor", "position"
  add_foreign_key "person_message", "person_message", column: "reply_to_id"
  add_foreign_key "person_message_member", "person"
  add_foreign_key "person_message_member", "person_message"
  add_foreign_key "person_motd", "motd"
  add_foreign_key "person_motd", "person"
  add_foreign_key "person_on_site", "person"
  add_foreign_key "person_online_course", "person"
  add_foreign_key "person_online_course", "position"
  add_foreign_key "person_page_visit", "person"
  add_foreign_key "person_passkey", "person"
  add_foreign_key "person_photo", "person"
  add_foreign_key "person_pod", "person"
  add_foreign_key "person_pod", "pod"
  add_foreign_key "person_pod", "timesheet", on_delete: :nullify
  add_foreign_key "person_pog", "person"
  add_foreign_key "person_pog", "timesheet", on_delete: :nullify
  add_foreign_key "person_position", "person"
  add_foreign_key "person_position", "position"
  add_foreign_key "person_role", "person"
  add_foreign_key "person_role", "role"
  add_foreign_key "person_slot", "person"
  add_foreign_key "person_slot", "slot"
  add_foreign_key "person_swag", "person"
  add_foreign_key "person_swag", "swag"
  add_foreign_key "person_team", "person"
  add_foreign_key "person_team", "team"
  add_foreign_key "pod", "pod", column: "mentor_pod_id", on_delete: :nullify
  add_foreign_key "pod", "slot", on_delete: :nullify
  add_foreign_key "position", "position", column: "parent_position_id", on_delete: :nullify
  add_foreign_key "position", "position", column: "training_position_id", on_delete: :nullify
  add_foreign_key "position", "team"
  add_foreign_key "position_credit", "position"
  add_foreign_key "position_lineup_member", "position"
  add_foreign_key "position_lineup_member", "position_lineup"
  add_foreign_key "position_role", "position"
  add_foreign_key "position_role", "role"
  add_foreign_key "prospective_application", "person", on_delete: :nullify
  add_foreign_key "prospective_application_log", "prospective_application"
  add_foreign_key "prospective_application_note", "prospective_application"
  add_foreign_key "provision", "person"
  add_foreign_key "sessions", "person"
  add_foreign_key "shift_coverage_position", "shift_coverage_group"
  add_foreign_key "slot", "position"
  add_foreign_key "slot", "slot", column: "parent_signup_slot_id", on_delete: :nullify
  add_foreign_key "slot", "slot", column: "trainee_slot_id", on_delete: :nullify
  add_foreign_key "slot", "slot", column: "trainer_slot_id", on_delete: :nullify
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "survey", "position", column: "mentoring_position_id", on_delete: :nullify
  add_foreign_key "survey", "position", on_delete: :nullify
  add_foreign_key "survey_answer", "slot", on_delete: :nullify
  add_foreign_key "survey_answer", "survey"
  add_foreign_key "survey_answer", "survey_group"
  add_foreign_key "survey_answer", "survey_question"
  add_foreign_key "survey_group", "survey"
  add_foreign_key "survey_question", "survey"
  add_foreign_key "survey_question", "survey_group"
  add_foreign_key "team_manager", "person"
  add_foreign_key "team_manager", "team"
  add_foreign_key "team_role", "role"
  add_foreign_key "team_role", "team"
  add_foreign_key "timesheet", "person"
  add_foreign_key "timesheet", "position"
  add_foreign_key "timesheet", "position", column: "desired_position_id", on_delete: :nullify
  add_foreign_key "timesheet", "slot", on_delete: :nullify
  add_foreign_key "timesheet_missing", "person"
  add_foreign_key "timesheet_missing_note", "timesheet_missing"
  add_foreign_key "timesheet_note", "timesheet"
  add_foreign_key "trainee_note", "person"
  add_foreign_key "trainee_note", "slot"
  add_foreign_key "trainee_status", "person"
  add_foreign_key "trainee_status", "slot"
  add_foreign_key "trainer_status", "person"
  add_foreign_key "trainer_status", "slot"
  add_foreign_key "trainer_status", "slot", column: "trainer_slot_id"
  add_foreign_key "vehicle", "person", on_delete: :nullify
end
