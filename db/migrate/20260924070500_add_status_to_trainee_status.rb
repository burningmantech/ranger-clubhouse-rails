# frozen_string_literal: true

# A training verdict is no longer a yes/no: a trainee is pending, passed, a
# no-show, or not passed. The old `passed` column stays for now because
# Clubhouse 2 shares this database and still reads and writes it
# (TrainingSessionController::scoreStudent). TraineeStatus mirrors every
# verdict into it until Clubhouse 2 moves over; a later migration drops it.
class AddStatusToTraineeStatus < ActiveRecord::Migration[8.1]
  # The table as it is today, so this migration never depends on the model
  # (the 20260408120000 precedent).
  class MigrationTraineeStatus < ActiveRecord::Base
    self.table_name = "trainee_status"
  end

  def up
    # The longest value, "not-passed", is ten characters.
    add_column :trainee_status, :status, :string, limit: 16, null: false, default: "pending"
    MigrationTraineeStatus.reset_column_information

    # Every row that exists records a verdict a trainer entered -- Clubhouse
    # 2's audit log carries `passed` on every create since 2022 -- so none is
    # backfilled as pending. A trainee marked "No or No Show" becomes
    # not-passed: the old score dialog did not tell the two apart.
    say_with_time "Backfilling trainee_status.status from passed" do
      MigrationTraineeStatus.where(passed: true).update_all(status: "passed") +
        MigrationTraineeStatus.where(passed: false).update_all(status: "not-passed")
    end
  end

  def down
    remove_column :trainee_status, :status
  end
end
