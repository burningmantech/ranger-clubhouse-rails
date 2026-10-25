# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::TakeStudentSurveyTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "skips when survey sessions are blank" do
    result = DashboardTasks::TakeStudentSurvey.check(
      facts(surveys: OpenStruct.new(sessions: []))
    )

    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "offers the optional student survey when sessions are present" do
    result = DashboardTasks::TakeStudentSurvey.check(
      facts(surveys: OpenStruct.new(sessions: [OpenStruct.new]))
    )

    assert_equal DashboardTask::STATUS_OPTIONAL, result.result
    assert_equal "take_student_survey", result.partial
  end

  test "skip_period is after-event" do
    assert_equal [DashboardTask::AFTER_EVENT], DashboardTasks::TakeStudentSurvey.skip_period
  end
end
