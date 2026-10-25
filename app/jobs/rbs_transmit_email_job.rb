# frozen_string_literal: true

# Sends a broadcast's emails through Amazon SES, many people to a call, away
# from the page the sender is looking at -- a broadcast can reach thousands of
# people.
#
# The recipients arrive as plain data (person id, and whether email may be used
# for them) so nothing about them can go stale between the send and the job.
class RbsTransmitEmailJob < RbsEmailJob
  # `queued_mode` is how email could leave when Send was pressed; a job queued
  # before it was recorded has none.
  def perform(broadcast_id, alert_id, sender_id, targets, subject, message, expires_at, queued_mode = nil)
    alert = Alert.find_by(id: alert_id)
    return if alert.nil?

    step :deliver do |step|
      Rbs.broadcast_email(alert, broadcast_id, sender_id, targets, subject, message, expires_at, queued_mode) do
        step.checkpoint!
      end
    end
  end
end
