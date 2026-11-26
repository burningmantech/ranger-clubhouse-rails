# frozen_string_literal: true

# role.new_user_eligible marked permissions to grant on activation and to keep
# through a retire, auditor or prospective reset. No permission carried it and
# nothing reads it any more, so it goes.
#
# It ships in the same deploy as the code that stopped reading the column. A
# deploy migrates while the previous release still answers requests, so until
# the roll ends that release fails on a status change and on Admin › Permissions.
class RemoveNewUserEligibleFromRole < ActiveRecord::Migration[8.1]
  def change
    remove_column :role, :new_user_eligible, :boolean, default: false, null: false
  end
end
