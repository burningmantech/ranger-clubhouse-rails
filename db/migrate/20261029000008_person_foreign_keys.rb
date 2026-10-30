# frozen_string_literal: true

# Nothing referenced person: a deleted account left rows in forty tables that
# still carried its id. Every table Person now cleans up on destroy (its
# dependent: associations, brought up to Clubhouse 2's ASSOC_TABLES list) gets
# a foreign key to person, RESTRICT, so a child the code forgets refuses the
# delete instead of dangling. The two nullable links an account may outlive
# (vehicle, the application that made it) are set NULL by the database.
#
# No key on the history tables: action_logs, log, legacy_log, request_log,
# mail_log, error_logs, timesheet_log, contact_log, bmid_export, outbound_links,
# person_status, broadcast*, person_message, help_hit, radio_log, bug_report,
# person_position_log and person_team_log keep a deleted person's id and name
# them "Deleted #id". None on an actor column (creator_person_id,
# reviewer_person_id, issued_by_id ...), on survey_answer.person_id (0 means
# anonymous), or on manual_review, mentee_status and radio_eligible, which have
# no model to clean them.
#
# Rows that already name a person who is gone are removed first, as the
# account's deletion would have removed them. Down drops the keys and puts the
# column types back; the removed rows do not come back.
class PersonForeignKeys < ActiveRecord::Migration[8.1]
  KEYS = [
    { table: "sessions", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "person_passkey", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: false, null: false } },
    { table: "person_swag", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "person_photo", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: false, null: false } },
    { table: "email_history", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "person_banner", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "person_certification", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "person_fka", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "person_language", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "person_favorite", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: false, null: false } },
    { table: "person_page_visit", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: false, null: false } },
    { table: "person_motd", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: false, null: false } },
    { table: "person_message_member", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "person_position", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "person_role", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "person_slot", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "person_team", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "timesheet", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "access_document", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "bmid", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "person_award", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "person_event", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: false, null: false } },
    { table: "person_intake", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: false, null: false } },
    { table: "person_intake_note", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: false, null: false } },
    { table: "person_mentor", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "person_online_course", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: false, null: false } },
    { table: "team_manager", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "timesheet_missing", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: false, null: false } },
    { table: "trainee_note", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "trainee_status", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "trainer_status", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "person_alert", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: false, null: false } },
    { table: "person_asset", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "person_pog", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "person_pod", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "person_on_site", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :bigint, unsigned: false, null: false } },
    { table: "oauth_code", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "provision", column: "person_id", parent: "person", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "vehicle", column: "person_id", parent: "person", on_delete: :nullify,
      was: { type: :bigint, unsigned: false, null: true } },
    { table: "prospective_application", column: "person_id", parent: "person", on_delete: :nullify,
      was: { type: :integer, unsigned: false, null: true } }
  ].freeze

  def up
    delete_orphans "trainee_status", "person_id", "person"  # 92 rows on 2026-10-29, 58 of them person_id 0
    delete_orphans "trainee_note", "person_id", "person"    # 12
    delete_orphans "person_mentor", "person_id", "person"   # 2
    delete_orphans "person_message_member", "person_id", "person"  # 1
    nullify_orphans "prospective_application", "person_id", "person"  # 2

    KEYS.each do |key|
      retype_to_parent(key)
      add_foreign_key key[:table], key[:parent], column: key[:column], on_delete: key[:on_delete]
    end
  end

  def down
    KEYS.reverse_each do |key|
      remove_foreign_key key[:table], column: key[:column]
      drop_key_index(key)
      restore_type(key)
    end
  end

  private

  # The child column takes the parent key's exact type (MariaDB refuses a key
  # between types that differ), keeping its own nullability.
  def retype_to_parent(key)
    parent_id = connection.columns(key[:parent]).find { |c| c.name == "id" }
    change_column key[:table], key[:column], parent_id.sql_type.start_with?("bigint") ? :bigint : :integer,
                  unsigned: parent_id.sql_type.include?("unsigned"),
                  null: connection.columns(key[:table]).find { |c| c.name == key[:column] }.null
  end

  def restore_type(key)
    change_column key[:table], key[:column], key[:was][:type], unsigned: key[:was][:unsigned], null: key[:was][:null]
  end

  # MariaDB indexes a key column that had no index, under the key's name; the
  # key's removal leaves it behind.
  def drop_key_index(key)
    index = connection.indexes(key[:table]).find { |i| i.columns == [key[:column]] && i.name.start_with?("fk_rails_") }
    remove_index key[:table], name: index.name if index
  end

  def delete_orphans(table, column, parent)
    execute "DELETE child FROM #{table} child LEFT JOIN #{parent} p ON p.id = child.#{column} WHERE p.id IS NULL"
  end

  def nullify_orphans(table, column, parent)
    execute "UPDATE #{table} child LEFT JOIN #{parent} p ON p.id = child.#{column} " \
            "SET child.#{column} = NULL WHERE child.#{column} IS NOT NULL AND p.id IS NULL"
  end
end
