# frozen_string_literal: true

require "test_helper"

class DashboardTasks::VerifyTimesheetsTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "no work done skips the task" do
    result = DashboardTasks::VerifyTimesheets.check(
      facts(did_work: false, timesheets_unverified: false, timesheet_confirmed: false)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "no work done skips even when timesheet confirmed" do
    result = DashboardTasks::VerifyTimesheets.check(
      facts(did_work: false, timesheets_unverified: false, timesheet_confirmed: true)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "work done, nothing unverified, timesheet confirmed completes the task" do
    result = DashboardTasks::VerifyTimesheets.check(
      facts(did_work: true, timesheets_unverified: false, timesheet_confirmed: true)
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
  end

  test "work done, nothing unverified, timesheet not confirmed needs action" do
    result = DashboardTasks::VerifyTimesheets.check(
      facts(did_work: true, timesheets_unverified: false, timesheet_confirmed: false)
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "verify_timesheets", result.partial
  end

  test "work done with unverified timesheets needs action" do
    result = DashboardTasks::VerifyTimesheets.check(
      facts(did_work: true, timesheets_unverified: true, timesheet_confirmed: false)
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "verify_timesheets", result.partial
  end

  test "work done with unverified timesheets needs action even if confirmed" do
    result = DashboardTasks::VerifyTimesheets.check(
      facts(did_work: true, timesheets_unverified: true, timesheet_confirmed: true)
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "verify_timesheets", result.partial
  end

  test "skip_period metadata" do
    assert_equal [DashboardTask::BEFORE_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::VerifyTimesheets.skip_period
  end

  test "task is immediate" do
    assert DashboardTasks::VerifyTimesheets.immediate
  end
end
