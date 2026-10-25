# frozen_string_literal: true

require "test_helper"

class DashboardTasks::VerifyTimesheetsFinishedTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "skips when no work was done" do
    result = DashboardTasks::VerifyTimesheetsFinished.check(
      facts(did_work: false, timesheets_unverified: false, timesheet_confirmed: true)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skips when timesheets are unverified" do
    result = DashboardTasks::VerifyTimesheetsFinished.check(
      facts(did_work: true, timesheets_unverified: true, timesheet_confirmed: true)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skips when timesheet is not confirmed" do
    result = DashboardTasks::VerifyTimesheetsFinished.check(
      facts(did_work: true, timesheets_unverified: false, timesheet_confirmed: false)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "completed when work done, verified, and confirmed" do
    result = DashboardTasks::VerifyTimesheetsFinished.check(
      facts(did_work: true, timesheets_unverified: false, timesheet_confirmed: true)
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
    assert_equal "verify_timesheets_finished", result.partial
  end

  test "skip_period excludes after-event and before-event" do
    assert_equal(
      [DashboardTask::AFTER_EVENT, DashboardTask::BEFORE_EVENT],
      DashboardTasks::VerifyTimesheetsFinished.skip_period
    )
  end
end
