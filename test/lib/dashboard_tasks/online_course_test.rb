# frozen_string_literal: true

require "test_helper"

class DashboardTasks::OnlineCourseTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  test "online_course_passed returns completed" do
    result = DashboardTasks::OnlineCourse.check(facts(online_course_passed: true))
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
    assert_equal "online_course_completed", result.partial
  end

  test "not enabled returns waiting" do
    result = DashboardTasks::OnlineCourse.check(
      facts(online_course_passed: false, online_course_enabled: false)
    )
    assert_equal DashboardTask::STATUS_WAITING, result.result
    assert_equal "online_course_waiting", result.partial
  end

  test "applicant without prev_completed returns not_available" do
    result = DashboardTasks::OnlineCourse.check(
      facts(
        online_course_passed: false,
        online_course_enabled: true,
        is_applicant: true,
        prev_completed: false
      )
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "online_course_blocked", result.partial
  end

  test "applicant with prev_completed falls through to action_needed" do
    result = DashboardTasks::OnlineCourse.check(
      facts(
        online_course_passed: false,
        online_course_enabled: true,
        is_applicant: true,
        prev_completed: true,
        is_echelon: false
      )
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "online_course_needed", result.partial
  end

  test "non-applicant non-echelon returns action_needed" do
    result = DashboardTasks::OnlineCourse.check(
      facts(
        online_course_passed: false,
        online_course_enabled: true,
        is_applicant: false,
        is_echelon: false
      )
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "online_course_needed", result.partial
  end

  test "echelon returns optional" do
    result = DashboardTasks::OnlineCourse.check(
      facts(
        online_course_passed: false,
        online_course_enabled: true,
        is_applicant: false,
        is_echelon: true
      )
    )
    assert_equal DashboardTask::STATUS_OPTIONAL, result.result
    assert_equal "online_course_needed", result.partial
  end

  test "skip_period metadata" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::OnlineCourse.skip_period
  end

  test "title metadata" do
    assert_equal "Read the Ranger Manual & Complete the Online Course",
                 DashboardTasks::OnlineCourse.title
  end
end
