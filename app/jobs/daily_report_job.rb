# frozen_string_literal: true

# The overnight summary of what happened in the Clubhouse: errors, permission
# and status changes, broadcast failures, and the settings that decide what
# people can do today.
class DailyReportJob < ApplicationJob
  # How far back every section of the report looks.
  PERIOD = 24.hours

  # The settings worth reading over morning coffee: each one either opens or
  # closes something people are trying to do right now.
  REPORTED_SETTINGS = [
    Setting::DASHBOARD_PERIOD,
    Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED,
    Setting::ONLINE_COURSE_DISABLED_ALLOW_SIGNUPS,
    Setting::ONLINE_COURSE_ENABLED,
    Setting::PHOTO_UPLOAD_ENABLE,
    Setting::TICKETING_PERIOD,
    Setting::TIMESHEET_CORRECTION_ENABLE,
    Setting::TRAINING_SEASONAL_ROLE_ENABLED
  ].freeze

  ROLE_EVENTS = %w[person-role-add person-role-remove].freeze
  SETTING_EVENTS = %w[setting-update].freeze
  EMAIL_EVENTS = %w[email-bouncing email-complaint].freeze

  # The most rows any one section will print.
  ERROR_LOG_LIMIT = 20
  ACTION_LOG_LIMIT = 1000
  FAILED_TASK_LIMIT = 50

  # One failed background task, in the words the report prints. Read out of the
  # queue here rather than in the email, because the queue often records that
  # something failed without recording anything about why.
  FailedTask = Data.define(:at, :task, :reason)

  def perform
    return if Setting.get_value(Setting::DAILY_REPORT_EMAIL).blank?

    DailyReportMailer.notify(
      failed_broadcasts: failed_broadcasts,
      error_logs: ErrorLog.find_for_query(last_day: true, page_size: ERROR_LOG_LIMIT)[:error_logs],
      role_logs: action_logs(ROLE_EVENTS),
      status_logs: status_logs,
      settings: Setting.get_value(REPORTED_SETTINGS),
      setting_logs: action_logs(SETTING_EVENTS),
      email_issues: action_logs(EMAIL_EVENTS),
      dashboard_period: EventDate.calculate_period,
      failed_jobs: failed_jobs,
      unknown_phones: BroadcastMessage.retrieve_unknown_phones_for_daily_report.to_a
    ).deliver_now
  end

  private

  def since
    Current.time - PERIOD
  end

  def failed_broadcasts
    Broadcast.with_failures
             .where(created_at: since..)
             .includes(:alert, :sender, :retry_person)
             .order(created_at: :desc)
             .to_a
  end

  def status_logs
    PersonStatus.where(created_at: since..)
                .includes(:person, :person_source)
                .order(:created_at)
                .to_a
  end

  def action_logs(events)
    ActionLog.find_for_query(lastday: true, page_size: ACTION_LOG_LIMIT, events:)[:action_logs]
  end

  # Failed background tasks are kept by the queue, which has its own database and
  # is not reachable everywhere the Clubhouse runs. Nothing rather than an empty
  # list, so the report can say it does not know instead of saying all is well.
  def failed_jobs
    return nil unless SolidQueue::FailedExecution.table_exists?

    SolidQueue::FailedExecution.includes(:job)
                               .where(created_at: since..)
                               .order(:created_at)
                               .limit(FAILED_TASK_LIMIT)
                               .map { |failed| describe_failure(failed) }
  rescue ActiveRecord::ActiveRecordError
    nil
  end

  def describe_failure(failed)
    reason = failed.error.blank? ? nil : [failed.exception_class, failed.message].compact_blank.join(": ")

    FailedTask.new(at: failed.created_at,
                   task: failed.job&.class_name || "Unknown task",
                   reason: reason.presence || "No reason recorded")
  end
end
