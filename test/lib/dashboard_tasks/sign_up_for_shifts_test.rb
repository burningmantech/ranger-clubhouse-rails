# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::SignUpForShiftsTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "blocked when online course not passed and person is auditor" do
    result = DashboardTasks::SignUpForShifts.check(
      facts(online_course_passed: false, is_auditor: true, is_applicant: false)
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "sign_up_for_shifts_blocked", result.partial
  end

  test "blocked when online course not passed and person is applicant" do
    result = DashboardTasks::SignUpForShifts.check(
      facts(online_course_passed: false, is_auditor: false, is_applicant: true)
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "sign_up_for_shifts_blocked", result.partial
  end

  test "schedule pending when dirt shifts unavailable and not echelon" do
    result = DashboardTasks::SignUpForShifts.check(
      facts(
        online_course_passed: true, is_auditor: false, is_applicant: false,
        dirt_shifts_available: false, is_echelon: false
      )
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "sign_up_for_shifts_schedule_pending", result.partial
  end

  test "completed when shift signups has slots, echelon bypasses schedule pending" do
    result = DashboardTasks::SignUpForShifts.check(
      facts(
        online_course_passed: true, is_auditor: false, is_applicant: false,
        dirt_shifts_available: false, is_echelon: true,
        shift_signups: OpenStruct.new(slot_count: 2)
      )
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
    assert_equal "sign_up_for_shifts_completed", result.partial
    assert result.sticky
  end

  test "action needed when dirt shifts available but no slots signed up" do
    result = DashboardTasks::SignUpForShifts.check(
      facts(
        online_course_passed: true, is_auditor: false, is_applicant: false,
        dirt_shifts_available: true, is_echelon: false,
        shift_signups: OpenStruct.new(slot_count: 0)
      )
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "sign_up_for_shifts_needed", result.partial
  end

  test "skip_period excludes post-event and after-event" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::SignUpForShifts.skip_period
  end
end
