# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::TakeAlphaSurveyTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "offers the survey when alpha_survey is present" do
    result = DashboardTasks::TakeAlphaSurvey.check(
      facts(surveys: OpenStruct.new(alpha_survey: true))
    )

    assert_equal DashboardTask::STATUS_OPTIONAL, result.result
    assert_equal "take_alpha_survey", result.partial
  end

  test "skips when alpha_survey is absent" do
    result = DashboardTasks::TakeAlphaSurvey.check(
      facts(surveys: OpenStruct.new(alpha_survey: false))
    )

    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skip_period is after-event" do
    assert_equal [DashboardTask::AFTER_EVENT], DashboardTasks::TakeAlphaSurvey.skip_period
  end
end
