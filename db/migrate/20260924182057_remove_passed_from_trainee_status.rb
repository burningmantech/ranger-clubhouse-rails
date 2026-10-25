# frozen_string_literal: true

# Clubhouse 2 is retired and will not run against this schema, so the
# `passed` boolean that the status was mirrored into can go. Rolling back
# re-adds it from the status: true for a pass, false for anything else.
class RemovePassedFromTraineeStatus < ActiveRecord::Migration[8.1]
  # The table as it is today, so this migration never depends on the model
  # (the 20260408120000 precedent).
  class MigrationTraineeStatus < ActiveRecord::Base
    self.table_name = "trainee_status"
  end

  def up
    remove_column :trainee_status, :passed
  end

  def down
    add_column :trainee_status, :passed, :boolean, null: false, default: false
    MigrationTraineeStatus.reset_column_information
    MigrationTraineeStatus.where(status: "passed").update_all(passed: true)
  end
end
