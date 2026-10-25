# frozen_string_literal: true

require "test_helper"

class DashboardTasks::VerifyPersonalInfoTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "completed when personal info already reviewed" do
    result = DashboardTasks::VerifyPersonalInfo.check(facts(has_reviewed_pi: true))
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
  end

  test "action needed for applicant (immediate false)" do
    result = DashboardTasks::VerifyPersonalInfo.check(
      facts(has_reviewed_pi: false, is_applicant: true, is_echelon: false, online_course_passed: true)
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal false, result.immediate
    assert_equal "verify_personal_info", result.partial
  end

  test "action needed for echelon (immediate false)" do
    result = DashboardTasks::VerifyPersonalInfo.check(
      facts(has_reviewed_pi: false, is_applicant: false, is_echelon: true, online_course_passed: true)
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal false, result.immediate
    assert_equal "verify_personal_info", result.partial
  end

  test "action needed for non-applicant non-echelon without online course passed" do
    result = DashboardTasks::VerifyPersonalInfo.check(
      facts(has_reviewed_pi: false, is_applicant: false, is_echelon: false, online_course_passed: false)
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal false, result.immediate
    assert_equal "verify_personal_info", result.partial
  end

  test "urgent and immediate for non-applicant non-echelon with online course passed" do
    result = DashboardTasks::VerifyPersonalInfo.check(
      facts(has_reviewed_pi: false, is_applicant: false, is_echelon: false, online_course_passed: true)
    )
    assert_equal DashboardTask::STATUS_URGENT, result.result
    assert_equal true, result.immediate
    assert_equal "verify_personal_info", result.partial
  end

  test "skip_period covers post and after event" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::VerifyPersonalInfo.skip_period
  end
end
