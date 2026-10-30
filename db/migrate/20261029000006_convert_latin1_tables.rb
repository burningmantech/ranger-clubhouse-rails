# frozen_string_literal: true

# Five tables kept Clubhouse 1's latin1 default and person_role utf8mb3, so a
# column added to them would refuse an emoji or a name outside Latin-1 while
# the rest of the database takes them. The character columns they hold are
# converted with the table; none of the latin1 ones held a non-ASCII byte.
#
# MariaDB widens a TEXT as it converts so it keeps its character capacity, and
# widens it again on every pass, so the two TEXT columns are pinned afterwards:
# MEDIUMTEXT going up, TEXT coming down.
#
# Down is lossy for timesheet_missing.partner: it was already utf8mb3 inside its
# latin1 table, and a character outside Latin-1 (two rows hold curly quotes)
# comes back as "?".
class ConvertLatin1Tables < ActiveRecord::Migration[8.1]
  TABLES = {
    "alert" => "latin1_swedish_ci",
    "event_dates" => "latin1_swedish_ci",
    "person_alert" => "latin1_swedish_ci",
    "timesheet_log" => "latin1_swedish_ci",
    "timesheet_missing" => "latin1_swedish_ci",
    "person_role" => "utf8mb3_unicode_ci"
  }.freeze

  TEXT_COLUMNS = { "alert" => "description", "timesheet_log" => "message" }.freeze

  def up
    TABLES.each_key { |table| convert(table, "utf8mb4_unicode_ci") }
    TEXT_COLUMNS.each { |table, column| change_column table, column, :text, size: :medium }
  end

  def down
    TABLES.each { |table, collation| convert(table, collation) }
    TEXT_COLUMNS.each { |table, column| change_column table, column, :text }
  end

  private

  def convert(table, collation)
    execute "ALTER TABLE #{table} CONVERT TO CHARACTER SET #{collation.split("_").first} COLLATE #{collation}"
  end
end
