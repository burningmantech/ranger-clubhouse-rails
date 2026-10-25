# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::AttendGreenDotMenteeShiftTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "skips when no green dot mentee art training is present" do
    arts = [OpenStruct.new(is_green_dot_mentee: false, mentee_slot: true)]
    result = DashboardTasks::AttendGreenDotMenteeShift.check(facts(art_trainings: arts))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skips when art_trainings is empty" do
    result = DashboardTasks::AttendGreenDotMenteeShift.check(facts(art_trainings: []))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skips when green dot mentee training has no mentee slot" do
    arts = [OpenStruct.new(is_green_dot_mentee: true, mentee_slot: nil)]
    result = DashboardTasks::AttendGreenDotMenteeShift.check(facts(art_trainings: arts))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "waiting when green dot mentee training has a mentee slot" do
    arts = [OpenStruct.new(is_green_dot_mentee: true, mentee_slot: true)]
    result = DashboardTasks::AttendGreenDotMenteeShift.check(facts(art_trainings: arts))
    assert_equal DashboardTask::STATUS_WAITING, result.result
    assert_equal "attend_green_dot_mentee_shift_waiting", result.partial
  end

  test "skip_period metadata" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::AttendGreenDotMenteeShift.skip_period
  end
end
