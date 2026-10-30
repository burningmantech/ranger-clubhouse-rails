# frozen_string_literal: true

# person_event.timesheet_confirmed is the record of a year's confirmation
# (ruling 2026-10-29); the copy on person was written by Clubhouse 2, read by
# nothing here, and still said "confirmed" on 828 rows whose year had passed.
class DropPersonTimesheetConfirmed < ActiveRecord::Migration[8.1]
  def change
    remove_column :person, :timesheet_confirmed, :boolean, default: false, null: false
    remove_column :person, :timesheet_confirmed_at, :datetime, precision: nil
  end
end
