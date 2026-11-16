# frozen_string_literal: true

# legacy_log has no message column (ruled 2026-10-28, see CreateLegacyLog), but
# a database built from an earlier draft of that migration kept one, NOT NULL
# with no default, so every insert that leaves it out fails. Dropped where it
# exists; a database built from the final migration is left as it is.
class DropLegacyLogMessage < ActiveRecord::Migration[8.1]
  def up
    remove_column :legacy_log, :message, if_exists: true
  end

  def down
    # Nothing to restore: the column was never part of the table.
  end
end
