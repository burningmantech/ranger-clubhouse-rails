# frozen_string_literal: true

# The Live mode of Admin › Request Log: LiveLogChannel over request_log.
class RequestLogLiveChannel < LiveLogChannel
  def self.feed = RequestLog.all

  private

  def authorized_roles = Admin::RequestLogsController.authorized_roles

  def update_partial = "admin/request_logs/live_update"
end
