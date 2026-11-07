# frozen_string_literal: true

# The Live mode of Admin › Action Logs: LiveLogChannel over action_logs,
# without the page-visit rows (ActionLog.live).
class ActionLogLiveChannel < LiveLogChannel
  private

  def authorized_roles = Admin::ActionLogsController.authorized_roles

  def feed = ActionLog.live

  def update_partial = "admin/action_logs/live_update"
end
