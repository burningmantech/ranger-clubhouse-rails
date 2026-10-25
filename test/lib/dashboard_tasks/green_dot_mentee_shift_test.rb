# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::GreenDotMenteeShiftTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "skip_period is post-event and after-event" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::GreenDotMenteeShift.skip_period
  end

  test "skips when no green dot mentee art training is present" do
    art = OpenStruct.new(is_green_dot_mentee: false)
    result = DashboardTasks::GreenDotMenteeShift.check(facts(art_trainings: [art]))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skips when there are no art trainings at all" do
    result = DashboardTasks::GreenDotMenteeShift.check(facts(art_trainings: []))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "completed when green dot mentee training has a mentee slot" do
    art = OpenStruct.new(is_green_dot_mentee: true, mentee_slot: OpenStruct.new)
    result = DashboardTasks::GreenDotMenteeShift.check(facts(art_trainings: [art]))
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
  end

  test "action needed when green dot mentee training has no mentee slot" do
    art = OpenStruct.new(is_green_dot_mentee: true, mentee_slot: nil)
    result = DashboardTasks::GreenDotMenteeShift.check(facts(art_trainings: [art]))
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "green_dot_mentee_shift_needed", result.partial
  end
end
