# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::SignUpForAlphaShiftTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "bonked person is skipped" do
    result = DashboardTasks::SignUpForAlphaShift.check(facts(is_any_bonked: true))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "alpha shift already done is completed" do
    result = DashboardTasks::SignUpForAlphaShift.check(
      facts(is_any_bonked: false, alpha_shift: true)
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
  end

  test "training not passed (nil training) is not available and blocked" do
    result = DashboardTasks::SignUpForAlphaShift.check(
      facts(is_any_bonked: false, alpha_shift: false, training: nil)
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "sign_up_for_alpha_shift_blocked", result.partial
  end

  test "training present but not passed is not available and blocked" do
    result = DashboardTasks::SignUpForAlphaShift.check(
      facts(
        is_any_bonked: false,
        alpha_shift: false,
        training: OpenStruct.new(status: "absent")
      )
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "sign_up_for_alpha_shift_blocked", result.partial
  end

  test "training passed, not prospective, alpha shifts available is action needed" do
    result = DashboardTasks::SignUpForAlphaShift.check(
      facts(
        is_any_bonked: false,
        alpha_shift: false,
        training: OpenStruct.new(status: Training::PASS),
        status: Person::ACTIVE,
        alpha_shifts_available: true
      )
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "sign_up_for_alpha_shift_needed", result.partial
  end

  test "training passed but prospective is waiting" do
    result = DashboardTasks::SignUpForAlphaShift.check(
      facts(
        is_any_bonked: false,
        alpha_shift: false,
        training: OpenStruct.new(status: Training::PASS),
        status: Person::PROSPECTIVE,
        alpha_shifts_available: true
      )
    )
    assert_equal DashboardTask::STATUS_WAITING, result.result
    assert_equal "sign_up_for_alpha_shift_waiting", result.partial
  end

  test "training passed, not prospective, but no alpha shifts available is waiting" do
    result = DashboardTasks::SignUpForAlphaShift.check(
      facts(
        is_any_bonked: false,
        alpha_shift: false,
        training: OpenStruct.new(status: Training::PASS),
        status: Person::ACTIVE,
        alpha_shifts_available: false
      )
    )
    assert_equal DashboardTask::STATUS_WAITING, result.result
    assert_equal "sign_up_for_alpha_shift_waiting", result.partial
  end
end
