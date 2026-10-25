# frozen_string_literal: true

# Clears out background tasks that failed long enough ago that no one is going
# to look into them now. Without this they pile up for good, and the daily
# report only ever shows the last day of them.
class ClearFailedTasksJob < ApplicationJob
  KEEP_FOR = 48.hours

  def perform
    return unless SolidQueue::FailedExecution.table_exists?

    # The queue's own way of throwing a failed task away: it takes the task and
    # the record of its failure together, a few hundred at a time, and leaves
    # the queue's bookkeeping straight.
    stale = SolidQueue::FailedExecution.where(created_at: ...KEEP_FOR.ago)
    count = stale.count
    stale.discard_all_in_batches
    Rails.logger.info("Cleared #{count} failed background #{"task".pluralize(count)}")
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("Could not clear failed background tasks: #{e.message}")
  end
end
