# frozen_string_literal: true

# What Solid Queue holds, read and repaired for Administration › Background
# Jobs: how many jobs sit in each state, one page of them, the processes
# serving the queue, and the three repairs. Every row is one of the gem's own
# models; this only chooses, counts and asks them.
module BackgroundJobs
  extend Pagy::Method

  PAGE_SIZE = 50

  # The states a job can be in, in the order the page shows them. Five are an
  # execution row each; finished is a stamp on the job itself.
  EXECUTIONS = {
    "failed" => SolidQueue::FailedExecution,
    "ready" => SolidQueue::ReadyExecution,
    "claimed" => SolidQueue::ClaimedExecution,
    "scheduled" => SolidQueue::ScheduledExecution,
    "blocked" => SolidQueue::BlockedExecution
  }.freeze
  STATES = (EXECUTIONS.keys + ["finished"]).freeze

  module_function

  def counts
    EXECUTIONS.transform_values(&:count).merge("finished" => SolidQueue::Job.finished.count)
  end

  # One page of jobs, newest first, as { jobs:, pagy: }. A page past the end
  # is the last page, so a delete on the last page lands on rows rather than
  # on the empty page Pagy would answer. Every execution is preloaded:
  # Job#status asks for all five. The count leaves them out: a status filter
  # joins its execution, which turns the preloads into joins.
  def page(page:, status: nil, queue_name: nil, class_name: nil)
    scope = scoped(status, queue_name, class_name)
    jobs = scope.includes(:ready_execution, :scheduled_execution, :blocked_execution, :failed_execution,
                          claimed_execution: :process).order(id: :desc)
    paging = { limit: PAGE_SIZE, count: scope.count, request: { params: {} } }
    pagy, records = pagy(:offset, jobs, page:, **paging)
    pagy, records = pagy(:offset, jobs, page: pagy.last, **paging) if pagy.page > pagy.last

    { jobs: records.to_a, pagy: }
  end

  def queue_names
    SolidQueue::Job.distinct_values_of(:queue_name).sort
  end

  # Supervisors first (no supervisor_id), then what they supervise.
  def workers
    SolidQueue::Process.includes(:supervisees).order(:supervisor_id, :id).to_a
  end

  # One failed job at a time, as the row's Retry does: each resets its
  # attempt counters, which the gem's bulk retry_all skips. Answers how many.
  def retry_failed
    count = 0
    SolidQueue::FailedExecution.includes(:job).find_each do |failed|
      failed.retry
      count += 1
    end
    count
  end

  # A finished job has no execution left to discard with it. A running one
  # raises SolidQueue::Execution::UndiscardableError.
  def delete(job)
    job.finished? ? job.destroy : job.discard
  end

  # Answers how many; the gem's batch discard does not.
  def delete_failed
    count = SolidQueue::FailedExecution.count
    SolidQueue::FailedExecution.discard_all_in_batches
    count
  end

  def scoped(status, queue_name, class_name)
    scope = case status
            when "finished" then SolidQueue::Job.finished
            when *EXECUTIONS.keys then SolidQueue::Job.joins(:"#{status}_execution")
            else SolidQueue::Job.all
            end
    scope = scope.where(queue_name:) if queue_name.present?
    scope = scope.where_like("class_name", "%#{SolidQueue::Job.sanitize_sql_like(class_name)}%") if class_name.present?
    scope
  end
end
