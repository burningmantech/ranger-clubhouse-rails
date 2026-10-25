# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::AttendTrainingTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  def training(status) = OpenStruct.new(status: status)

  # --- guard: online course not passed ---

  test "online course not passed and applicant is not available" do
    result = DashboardTasks::AttendTraining.check(
      facts(online_course_passed: false, is_applicant: true, is_auditor: false)
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "attend_training_signup", result.partial
  end

  test "online course not passed and auditor is not available" do
    result = DashboardTasks::AttendTraining.check(
      facts(online_course_passed: false, is_applicant: false, is_auditor: true)
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "attend_training_signup", result.partial
  end

  test "online course not passed and neither applicant nor auditor is skipped" do
    result = DashboardTasks::AttendTraining.check(
      facts(online_course_passed: false, is_applicant: false, is_auditor: false)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  # --- guard: no training shift ---

  test "no training shift and applicant is not available" do
    result = DashboardTasks::AttendTraining.check(
      facts(online_course_passed: true, training: training(Training::NO_SHIFT),
            is_applicant: true, is_auditor: false)
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "attend_training_signup", result.partial
  end

  test "no training shift and neither applicant nor auditor is skipped" do
    result = DashboardTasks::AttendTraining.check(
      facts(online_course_passed: true, training: training(Training::NO_SHIFT),
            is_applicant: false, is_auditor: false)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  # --- PASS ---

  test "passed training as cheetah cub is completed with cheetah partial" do
    result = DashboardTasks::AttendTraining.check(
      facts(online_course_passed: true, training: training(Training::PASS),
            is_cheetah_cub: true)
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
    assert_equal "attend_training_cheetah", result.partial
  end

  test "passed training as applicant is completed with no partial" do
    result = DashboardTasks::AttendTraining.check(
      facts(online_course_passed: true, training: training(Training::PASS),
            is_cheetah_cub: false, is_applicant: true, is_auditor: false)
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
    assert_nil result.partial
  end

  test "passed training as auditor is completed with no partial" do
    result = DashboardTasks::AttendTraining.check(
      facts(online_course_passed: true, training: training(Training::PASS),
            is_cheetah_cub: false, is_applicant: false, is_auditor: true)
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
    assert_nil result.partial
  end

  test "passed training as regular ranger is completed with art partial" do
    result = DashboardTasks::AttendTraining.check(
      facts(online_course_passed: true, training: training(Training::PASS),
            is_cheetah_cub: false, is_applicant: false, is_auditor: false)
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
    assert_equal "attend_training_art", result.partial
  end

  # --- NO_SHOW ---

  test "no-show training is urgent and immediate" do
    result = DashboardTasks::AttendTraining.check(
      facts(online_course_passed: true, training: training(Training::NO_SHOW))
    )
    assert_equal DashboardTask::STATUS_URGENT, result.result
    assert_equal "attend_training_no_show", result.partial
    assert result.immediate
  end

  # --- FAIL ---

  test "failed training is urgent and immediate" do
    result = DashboardTasks::AttendTraining.check(
      facts(online_course_passed: true, training: training(Training::FAIL))
    )
    assert_equal DashboardTask::STATUS_URGENT, result.result
    assert_equal "attend_training_fail", result.partial
    assert result.immediate
  end

  # --- PENDING ---

  test "pending training needs action" do
    result = DashboardTasks::AttendTraining.check(
      facts(online_course_passed: true, training: training(Training::PENDING))
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "attend_training_pending", result.partial
  end

  # --- else (unknown status) ---

  test "unknown training status is skipped" do
    result = DashboardTasks::AttendTraining.check(
      facts(online_course_passed: true, training: training("something-else"))
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  # --- class metadata ---

  test "title" do
    assert_equal "Attend In-Person Training", DashboardTasks::AttendTraining.title
  end

  test "skip_period" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::AttendTraining.skip_period
  end
end
