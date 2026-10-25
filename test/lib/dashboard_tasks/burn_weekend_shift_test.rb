# frozen_string_literal: true

require "test_helper"

class DashboardTasks::BurnWeekendShiftTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "completed when burn_weekend_signup is present" do
    result = DashboardTasks::BurnWeekendShift.check(facts(burn_weekend_signup: true))
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
    assert_equal "burn_weekend_shift_completed", result.partial
  end

  test "action needed when not signed up but burn_weekend_available" do
    result = DashboardTasks::BurnWeekendShift.check(
      facts(burn_weekend_signup: false, burn_weekend_available: true)
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "burn_weekend_shift_needed", result.partial
  end

  test "skip when neither signed up nor available" do
    result = DashboardTasks::BurnWeekendShift.check(
      facts(burn_weekend_signup: false, burn_weekend_available: false)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skip_period metadata" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::BurnWeekendShift.skip_period
  end
end
