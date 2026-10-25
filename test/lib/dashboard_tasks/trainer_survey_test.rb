# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::TrainerSurveyTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "surveys.trainers present -> optional with partial" do
    result = DashboardTasks::TrainerSurvey.check(
      facts(surveys: OpenStruct.new(trainers: [OpenStruct.new]))
    )
    assert_equal DashboardTask::STATUS_OPTIONAL, result.result
    assert_equal "trainer_survey", result.partial
  end

  test "surveys.trainers blank -> skip" do
    result = DashboardTasks::TrainerSurvey.check(
      facts(surveys: OpenStruct.new(trainers: []))
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skip_period is after-event" do
    assert_equal [DashboardTask::AFTER_EVENT], DashboardTasks::TrainerSurvey.skip_period
  end
end
