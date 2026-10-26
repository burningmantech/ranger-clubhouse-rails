# frozen_string_literal: true

# Sends a broadcast's queued texts through Twilio, one request a person, away
# from the page the sender is looking at -- a broadcast can reach thousands of
# people. Send and Retry both queue the texts, then this job.
class RbsTransmitSmsJob < ApplicationJob
  # One run a broadcast at a time, so a Retry clicked twice cannot send a text
  # twice, while another broadcast's texts -- an emergency's -- never wait
  # behind it. Three hours covers the whole roster, plus the queue.
  limits_concurrency to: 1, key: ->(broadcast_id, *) { broadcast_id }, duration: 3.hours

  # A deploy stops a run at the checkpoint after each round, and the job picks
  # up the texts still queued -- provided the round ends within Solid Queue's
  # shutdown timeout; past it the job is released and starts over, and the
  # round's texts, marked send-unconfirmed before they went, are not sent
  # again. An error is never a reason to pick up again.
  include ActiveJob::Continuable

  self.resume_errors_after_advancing = false

  # `held` is whether the text sandbox was on when Send or Retry was pressed.
  def perform(broadcast_id, held)
    step :deliver do |step|
      Rbs.deliver_queued_sms(broadcast_id, held) { step.checkpoint! }
    end
  end
end
