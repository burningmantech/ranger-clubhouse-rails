# frozen_string_literal: true

require "test_helper"

# Every table is utf8mb4 / utf8mb4_unicode_ci. A table in another charset refuses characters the rest of
# the database takes (latin1 an emoji or a Greek name, utf8mb3 an emoji), and a column in another
# collation cannot be compared with one of the rest.
class TableCharsetTest < ActiveSupport::TestCase
  STANDARD = { charset: "utf8mb4", collation: "utf8mb4_unicode_ci" }.freeze

  # The one table Clubhouse 2 left in another collation. Converting it means deleting its line. Nothing
  # is added: a table that turns up here is converted, or created again with its charset named.
  LEGACY = { "radio_log" => "utf8mb4_general_ci" }.freeze

  test "every table is utf8mb4_unicode_ci, apart from the one Clubhouse 2 left" do
    connection = ActiveRecord::Base.lease_connection
    others = connection.tables.index_with { |table| connection.table_options(table)[:collation] }
                       .reject { |_table, collation| collation == STANDARD[:collation] }

    assert_empty others.to_a - LEGACY.to_a, "tables to convert, or to create again with their charset named"
    assert_empty LEGACY.to_a - others.to_a, "lines to delete from LEGACY"
  end

  # A test database's own default collation is its MariaDB's (utf8mb4_uca1400_ai_ci on 12.3), so this
  # fails once create_table stops naming one (config/initializers/active_record_extensions.rb).
  test "create_table names utf8mb4_unicode_ci itself, unless the caller names a charset" do
    connection = ActiveRecord::Base.lease_connection
    connection.create_table(:charset_probe, temporary: true)
    connection.create_table(:charset_probe_ascii, temporary: true, charset: "ascii")

    assert_equal STANDARD, connection.table_options(:charset_probe).slice(:charset, :collation)
    assert_equal "ascii", connection.table_options(:charset_probe_ascii)[:charset]
  ensure
    connection.drop_table(:charset_probe, :charset_probe_ascii, temporary: true, if_exists: true)
  end
end
