# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::SignUpForTrainingTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "completed when training already has a shift" do
    result = DashboardTasks::SignUpForTraining.check(
      facts(training: OpenStruct.new(status: "passed"))
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
  end

  test "not available when no shift and online course not passed" do
    result = DashboardTasks::SignUpForTraining.check(
      facts(training: OpenStruct.new(status: Training::NO_SHIFT), online_course_passed: false)
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "sign_up_for_training_blocked", result.partial
  end

  test "action needed when no shift, course passed, and trainings available" do
    result = DashboardTasks::SignUpForTraining.check(
      facts(
        training: OpenStruct.new(status: Training::NO_SHIFT),
        online_course_passed: true,
        trainings_available: true
      )
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "sign_up_for_training_needed", result.partial
  end

  test "waiting when no shift, course passed, and no trainings available" do
    result = DashboardTasks::SignUpForTraining.check(
      facts(
        training: OpenStruct.new(status: Training::NO_SHIFT),
        online_course_passed: true,
        trainings_available: false
      )
    )
    assert_equal DashboardTask::STATUS_WAITING, result.result
    assert_equal "sign_up_for_training_waiting", result.partial
  end

  test "title" do
    assert_equal "Sign Up for In-Person Training", DashboardTasks::SignUpForTraining.title
  end

  test "skip_period covers post-event and after-event" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::SignUpForTraining.skip_period
  end
end
