# frozen_string_literal: true

require "test_helper"

class DashboardTasks::AttendCheetahCubShiftTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "skips when not a cheetah cub" do
    result = DashboardTasks::AttendCheetahCubShift.check(facts(is_cheetah_cub: false))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "action needed when cheetah cub shift signup is pending" do
    result = DashboardTasks::AttendCheetahCubShift.check(
      facts(is_cheetah_cub: true, cheetah_cub_shift: { "status" => "pending" })
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "attend_cheetah_cub_shift_pending", result.partial
  end

  test "skips when cheetah cub but no signup" do
    result = DashboardTasks::AttendCheetahCubShift.check(
      facts(is_cheetah_cub: true, cheetah_cub_shift: nil)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skips when cheetah cub and signup status is not pending" do
    result = DashboardTasks::AttendCheetahCubShift.check(
      facts(is_cheetah_cub: true, cheetah_cub_shift: { "status" => "approved" })
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skip_period covers post-event and after-event" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::AttendCheetahCubShift.skip_period
  end
end
