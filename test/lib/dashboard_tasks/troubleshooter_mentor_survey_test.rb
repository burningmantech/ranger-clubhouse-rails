# frozen_string_literal: true

require "test_helper"

class DashboardTasks::TroubleshooterMentorSurveyTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "skips when ts_mentor_worked is false" do
    result = DashboardTasks::TroubleshooterMentorSurvey.check(facts(ts_mentor_worked: false))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "skips when ts_mentor_worked is nil" do
    result = DashboardTasks::TroubleshooterMentorSurvey.check(facts(ts_mentor_worked: nil))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "action needed when ts_mentor_worked is true" do
    result = DashboardTasks::TroubleshooterMentorSurvey.check(facts(ts_mentor_worked: true))
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "troubleshooter_mentor_survey", result.partial
  end

  test "period metadata" do
    assert_equal [DashboardTask::DURING_EVENT, DashboardTask::POST_EVENT],
                 DashboardTasks::TroubleshooterMentorSurvey.period
  end
end
