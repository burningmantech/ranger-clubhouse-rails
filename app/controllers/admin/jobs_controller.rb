# frozen_string_literal: true

# What Solid Queue holds: every job by state, the processes serving the queue,
# and the way to retry a failed job or delete one. Tech Team only: a retry
# runs code, a delete loses a job for good, and the arguments on show can
# carry addresses.
class Admin::JobsController < ApplicationController
  layout "admin"

  authorize_role [Role::TECH_NINJA], message: "Tech Ninja role required to manage background jobs."

  before_action :set_job, only: [:retry, :destroy]

  def index
    @form = JobFilterForm.new(filter_params)
    @counts = BackgroundJobs.counts
    result = BackgroundJobs.page(**@form.active_filters, page: @form.page)
    @jobs = result[:jobs]
    @pagy = result[:pagy]
    @queue_names = BackgroundJobs.queue_names
    @workers = BackgroundJobs.workers
  end

  def retry
    unless @job.failed?
      redirect_back_or_to admin_jobs_path, error: "Job #{@job.id} is not failed, so there is nothing to retry."
      return
    end

    @job.retry
    record("background-job-retry", "Retried job #{job_label}", **job_data)
    redirect_back_or_to admin_jobs_path, success: "Job #{job_label} is back on the #{@job.queue_name} queue."
  end

  def destroy
    BackgroundJobs.delete(@job)
    record("background-job-delete", "Deleted job #{job_label}", **job_data)
    redirect_back_or_to admin_jobs_path, success: "Job #{job_label} deleted."
  rescue SolidQueue::Execution::UndiscardableError
    redirect_back_or_to admin_jobs_path,
                        error: "Job #{@job.id} is running and cannot be deleted. Wait for it to finish or fail."
  end

  def retry_all
    count = BackgroundJobs.retry_failed
    failed = helpers.pluralize(count, "failed job")
    record("background-job-retry-all", "Retried all #{failed}", count:)
    redirect_back_or_to admin_jobs_path, success: "#{failed} put back on the queue."
  end

  def destroy_failed
    count = BackgroundJobs.delete_failed
    failed = helpers.pluralize(count, "failed job")
    record("background-job-delete-failed", "Deleted all #{failed}", count:)
    redirect_back_or_to admin_jobs_path, success: "#{failed} deleted."
  end

  private

  def set_job
    @job = SolidQueue::Job.find(params.expect!(:id))
  end

  def filter_params
    scoped_params(JobFilterForm::PARAM_SCOPE, :status, :queue_name, :class_name, :page)
  end

  def job_label
    helpers.job_label(@job)
  end

  def job_data
    { job_id: @job.id, class_name: @job.class_name }
  end

  def record(event, message, **data)
    ActionLog.record(Current.person, event, message, data)
  end
end
