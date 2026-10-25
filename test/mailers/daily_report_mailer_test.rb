# frozen_string_literal: true

require "test_helper"

class DailyReportMailerTest < ActionMailer::TestCase
  # The queue keeps failed tasks in a database of its own that no test can
  # reach, so the rows are built by hand -- otherwise only the "cannot reach the
  # queue" path would ever be rendered, and a mistake in the row itself would go
  # unnoticed until the first task failed.

  setup do
    Setting.find_or_initialize_by(name: Setting::DAILY_REPORT_EMAIL).update!(value: "daily@example.com")
  end

  test "a failed task is listed with what failed and why" do
    failed = DailyReportJob::FailedTask.new(at: Time.zone.local(2026, 8, 22, 3, 0, 0),
                                            task: "PhotoPendingJob",
                                            reason: "Net::SMTPServerBusy: the mail server said no")

    body = report(failed_jobs: [failed]).body.to_s

    assert_includes body, "Failed Background Tasks (1)"
    assert_includes body, "PhotoPendingJob"
    assert_includes body, "Net::SMTPServerBusy: the mail server said no"
  end

  test "the report says so when it cannot reach the queue" do
    body = report(failed_jobs: nil).body.to_s

    assert_includes body, "cannot reach the queue"
  end

  test "no failed tasks reads as good news rather than an empty table" do
    body = report(failed_jobs: []).body.to_s

    assert_includes body, "No tasks failed."
  end

  private

  def report(**overrides)
    DailyReportMailer.notify(**{
      failed_broadcasts: Broadcast.none,
      error_logs: ErrorLog.none,
      role_logs: [],
      status_logs: PersonStatus.none,
      settings: Setting.get_value(DailyReportJob::REPORTED_SETTINGS),
      setting_logs: [],
      email_issues: [],
      dashboard_period: EventDate.calculate_period,
      failed_jobs: [],
      unknown_phones: BroadcastMessage.none
    }.merge(overrides))
  end
end
