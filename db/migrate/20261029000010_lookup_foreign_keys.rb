# frozen_string_literal: true

# Keys to the lookup and record parents: award, asset, certification, swag,
# motd, alert, survey (and its groups and questions), oauth_client,
# prospective_application, position_lineup, shift_coverage_group,
# person_message, person_photo and broadcast. RESTRICT where the parent's
# model removes the child on destroy; SET NULL on the optional links.
#
# Left without a key, on purpose: person_online_course.online_course_id
# (0 means none), access_document_changes.record_id (693 rows are the history
# of deleted documents), mail_log and person_message's broadcast columns, and
# help_hit (history), and person_message_member.last_read_message_id, a
# watermark (the id before the newest unread row) rather than a reference.
#
# Rows already naming a parent that is gone go first: read marks of deleted
# messages of the day and checkouts of deleted assets are removed, as the
# parent's deletion would have removed them. Down drops the keys and puts the
# column types back; the removed rows do not come back.
class LookupForeignKeys < ActiveRecord::Migration[8.1]
  KEYS = [
    { table: "person_award", column: "award_id", parent: "award", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "person_asset", column: "asset_id", parent: "asset", on_delete: :restrict,
      was: { type: :bigint, unsigned: true, null: false } },
    { table: "person_asset", column: "attachment_id", parent: "asset_attachment", on_delete: :nullify,
      was: { type: :bigint, unsigned: true, null: true } },
    { table: "person_certification", column: "certification_id", parent: "certification", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "person_swag", column: "swag_id", parent: "swag", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "person", column: "tshirt_swag_id", parent: "swag", on_delete: :nullify,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "person", column: "tshirt_secondary_swag_id", parent: "swag", on_delete: :nullify,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "person", column: "long_sleeve_swag_id", parent: "swag", on_delete: :nullify,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "person_motd", column: "motd_id", parent: "motd", on_delete: :restrict,
      was: { type: :bigint, unsigned: false, null: false } },
    { table: "person_alert", column: "alert_id", parent: "alert", on_delete: :restrict,
      was: { type: :bigint, unsigned: false, null: false } },
    { table: "broadcast", column: "alert_id", parent: "alert", on_delete: :restrict,
      was: { type: :bigint, unsigned: false, null: false } },
    { table: "survey_group", column: "survey_id", parent: "survey", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "survey_question", column: "survey_id", parent: "survey", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "survey_answer", column: "survey_id", parent: "survey", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "survey_question", column: "survey_group_id", parent: "survey_group", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "survey_answer", column: "survey_group_id", parent: "survey_group", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "survey_answer", column: "survey_question_id", parent: "survey_question", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "oauth_code", column: "oauth_client_id", parent: "oauth_client", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "prospective_application_note", column: "prospective_application_id", parent: "prospective_application", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "prospective_application_log", column: "prospective_application_id", parent: "prospective_application", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "position_lineup_member", column: "position_lineup_id", parent: "position_lineup", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "shift_coverage_position", column: "shift_coverage_group_id", parent: "shift_coverage_group", on_delete: :restrict,
      was: { type: :bigint, unsigned: false, null: false } },
    { table: "person_message_member", column: "person_message_id", parent: "person_message", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: false } },
    { table: "person_message", column: "reply_to_id", parent: "person_message", on_delete: :restrict,
      was: { type: :integer, unsigned: false, null: true } },
    { table: "person", column: "person_photo_id", parent: "person_photo", on_delete: :nullify,
      was: { type: :bigint, unsigned: false, null: true } },
    { table: "broadcast_message", column: "broadcast_id", parent: "broadcast", on_delete: :restrict,
      was: { type: :bigint, unsigned: false, null: true } }
  ].freeze

  def up
    delete_orphans "person_motd", "motd_id", "motd"      # 637 rows on 2026-10-29
    delete_orphans "person_asset", "asset_id", "asset"   # 70
    nullify_orphans "person", "person_photo_id", "person_photo"  # 1

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
