# frozen_string_literal: true

# The Live mode of Admin › Action Logs: LiveLogChannel over every action_logs
# row, page visits among them (the owner's ruling, 2026-11-07), reading only
# the columns a Live row shows.
class ActionLogLiveChannel < LiveLogChannel
  def self.feed = ActionLog.live_columns

  private

  def authorized_roles = Admin::ActionLogsController.authorized_roles

  def update_partial = "admin/action_logs/live_update"
end
