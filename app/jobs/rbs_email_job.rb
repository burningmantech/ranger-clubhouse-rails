# frozen_string_literal: true

# What the two broadcast email jobs share: one lock between them, and stopping
# only between batches.
class RbsEmailJob < ApplicationJob
  # One email job at a time, a send or a retry: two side by side would send
  # at twice the account's rate, and a retry clicked twice would race itself.
  # The group is what makes the lock shared -- by default it is the class name.
  # Three hours covers the whole roster at a call a second, plus the queue.
  limits_concurrency to: 1, group: "rbs-email", key: "rbs-email", duration: 3.hours

  # A deploy stops a run at the checkpoint after each committed batch, and the
  # job picks up again there -- provided the call in flight ends within Solid
  # Queue's shutdown timeout; past it the job is released and starts over. An
  # error is never a reason to pick up again: the batch it stopped may already
  # have gone.
  include ActiveJob::Continuable

  self.resume_errors_after_advancing = false
end
