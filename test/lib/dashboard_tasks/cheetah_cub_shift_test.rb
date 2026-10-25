# frozen_string_literal: true

require "test_helper"

class DashboardTasks::CheetahCubShiftTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "skips when not a cheetah cub" do
    result = DashboardTasks::CheetahCubShift.check(facts(is_cheetah_cub: false))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "completed when cheetah cub already has a shift" do
    result = DashboardTasks::CheetahCubShift.check(
      facts(is_cheetah_cub: true, cheetah_cub_shift: true)
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
  end

  test "urgent when no shift and online course passed" do
    result = DashboardTasks::CheetahCubShift.check(
      facts(is_cheetah_cub: true, cheetah_cub_shift: false, online_course_passed: true)
    )
    assert_equal DashboardTask::STATUS_URGENT, result.result
    assert_equal "cheetah_cub_shift_needed", result.partial
  end

  test "action needed when no shift and online course not passed" do
    result = DashboardTasks::CheetahCubShift.check(
      facts(is_cheetah_cub: true, cheetah_cub_shift: false, online_course_passed: false)
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "cheetah_cub_shift_needed", result.partial
  end

  test "skip_period covers post-event and after-event" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::CheetahCubShift.skip_period
  end
end
