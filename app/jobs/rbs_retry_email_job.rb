# frozen_string_literal: true

# Sends the emails of a broadcast that failed the first time, away from the page
# that asked for it. A broadcast can have thousands of them, and doing that
# while someone waits would time the request out part-way through.
class RbsRetryEmailJob < RbsEmailJob
  # `queued_mode` is how email could leave when Retry was pressed; a job
  # queued before it was recorded has none.
  def perform(broadcast_id, message_ids, queued_mode = nil)
    step :deliver do |step|
      Rbs.deliver_retried_emails(broadcast_id, message_ids, queued_mode) { step.checkpoint! }
    end
  end
end
