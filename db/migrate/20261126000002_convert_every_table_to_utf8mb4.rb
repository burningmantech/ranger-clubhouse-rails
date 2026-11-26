# frozen_string_literal: true

# Every table becomes utf8mb4 / utf8mb4_unicode_ci. Forty-seven were not:
#
# - Thirty in db/schema.rb and Rails' own two were latin1. A table created
#   without a charset takes its database's default, and where these were
#   created that was latin1. A latin1 column refuses any character outside
#   Latin-1, an emoji or a Greek name, and the write fails.
# - Fifteen were utf8mb3, as Clubhouse 2 left them. A utf8mb3 column refuses
#   any four-byte character: an emoji in an asset's notes failed the save.
#   Three of them compared as utf8mb3_general_ci and now compare as the rest do.
#
# Column by column rather than ALTER TABLE ... CONVERT TO, which rewrites every
# character column of a table. That would turn person_passkey.external_id from
# ascii_bin to a collation that ignores capitals, and two passkey ids can
# differ by capitals alone; it would take utf8mb4_bin off the JSON columns and
# widen every TEXT to MEDIUMTEXT. Changing only the columns in the old
# collation leaves each column's type, default and comment as it was. MariaDB
# converts what the latin1 columns hold (utf8mb3 text is utf8mb4 as it stands),
# and refuses the change rather than cut a value that no longer fits.
#
# A table already converted is left as it is, so a run that stopped part way
# is simply run again. The table's own default changes last.
#
# The way back fails while one of these columns holds a character its old
# charset has no place for, rather than losing it.
class ConvertEveryTableToUtf8mb4 < ActiveRecord::Migration[8.1]
  COLLATION = "utf8mb4_unicode_ci"

  # The tables, by the collation each had.
  TABLES = {
    "latin1_swedish_ci" => %w[
      active_storage_attachments active_storage_blobs active_storage_variant_records ar_internal_metadata
      bmid_title bug_report email_suppression mail_template outbound_links person_favorite
      person_message_member person_on_site person_page_visit person_passkey schema_migrations sessions
      shift_coverage_group shift_coverage_position solid_cable_messages solid_queue_batch_executions
      solid_queue_batches solid_queue_blocked_executions solid_queue_claimed_executions
      solid_queue_failed_executions solid_queue_jobs solid_queue_pauses solid_queue_processes
      solid_queue_ready_executions solid_queue_recurring_executions solid_queue_recurring_tasks
      solid_queue_scheduled_executions solid_queue_semaphores
    ],
    "utf8mb3_unicode_ci" => %w[
      access_document access_document_changes asset bmid manual_review person_asset person_position
      person_slot position_credit radio_eligible role timesheet
    ],
    "utf8mb3_general_ci" => %w[asset_attachment mentee_status trainee_status]
  }.freeze

  def up
    TABLES.each { |was, tables| tables.each { |table| convert(table, from: was, to: COLLATION) } }
  end

  def down
    TABLES.each { |was, tables| tables.each { |table| convert(table, from: COLLATION, to: was) } }
  end

  private

  def convert(table, from:, to:)
    change_table table, bulk: true do |t|
      connection.columns(table).each do |column|
        t.change column.name, nil, collation: to if column.collation == from
      end
    end
    return unless connection.table_options(table)[:collation] == from

    execute "ALTER TABLE #{connection.quote_table_name(table)} " \
            "DEFAULT CHARACTER SET #{to.split("_").first} COLLATE #{to}"
  end
end
