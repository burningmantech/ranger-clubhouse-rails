# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::AttendAlphaShiftTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "bonked status blocks the task" do
    result = DashboardTasks::AttendAlphaShift.check(facts(status: Person::BONKED))
    assert_equal DashboardTask::STATUS_BLOCKED, result.result
    assert_equal "attend_alpha_shift_bonked", result.partial
  end

  test "uberbonked status blocks the task" do
    result = DashboardTasks::AttendAlphaShift.check(facts(status: Person::UBERBONKED))
    assert_equal DashboardTask::STATUS_BLOCKED, result.result
    assert_equal "attend_alpha_shift_bonked", result.partial
  end

  test "alpha shift pending needs action" do
    result = DashboardTasks::AttendAlphaShift.check(
      facts(status: Person::ACTIVE, alpha_shift: { status: Training::PENDING })
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "attend_alpha_shift_pending", result.partial
  end

  test "alpha shift with non-pending status is urgent (missed)" do
    result = DashboardTasks::AttendAlphaShift.check(
      facts(status: Person::ACTIVE, alpha_shift: { status: Training::FAIL })
    )
    assert_equal DashboardTask::STATUS_URGENT, result.result
    assert_equal "attend_alpha_shift_missed", result.partial
  end

  test "no alpha shift and none available is not available" do
    result = DashboardTasks::AttendAlphaShift.check(
      facts(status: Person::ACTIVE, alpha_shift: nil, alpha_shifts_available: false)
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "attend_alpha_shift_not_available", result.partial
  end

  test "no alpha shift but shifts available prompts sign up" do
    result = DashboardTasks::AttendAlphaShift.check(
      facts(status: Person::ACTIVE, alpha_shift: nil, alpha_shifts_available: true)
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "attend_alpha_shift_sign_up", result.partial
  end

  test "title metadata" do
    assert_equal "Attend Your Alpha Shift", DashboardTasks::AttendAlphaShift.title
  end
end
