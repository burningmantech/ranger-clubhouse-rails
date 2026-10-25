# frozen_string_literal: true

# The TimesheetLog::DELETE_MISTAKE constant (and its display label) were
# ported ahead of the shift check in/out feature, but the action enum never
# gained the value — writing it truncated to an empty string.
class AddDeleteMistakeToTimesheetLogAction < ActiveRecord::Migration[8.1]
  ACTIONS = %w[unconfirmed confirmed signon signoff created update delete review verify unverified].freeze

  def up
    change_column :timesheet_log, :action, enum_type(ACTIONS + ["delete-mistake"]), null: false
  end

  def down
    change_column :timesheet_log, :action, enum_type(ACTIONS), null: false
  end

  private

  def enum_type(values)
    "enum(#{values.map { |value| "'#{value}'" }.join(",")})"
  end
end
