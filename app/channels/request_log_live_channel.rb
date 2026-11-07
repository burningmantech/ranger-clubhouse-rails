# frozen_string_literal: true

# The Live mode of Admin › Request Log: LiveLogChannel over request_log.
class RequestLogLiveChannel < LiveLogChannel
  private

  def authorized_roles = Admin::RequestLogsController.authorized_roles

  def feed = RequestLog.all

  def update_partial = "admin/request_logs/live_update"
end
