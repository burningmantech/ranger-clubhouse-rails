# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::ArtTrainingTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  def art(status) = OpenStruct.new(status: status)

  # Branch: guard -> skip when no art trainings.
  test "skips when there are no art trainings" do
    result = DashboardTasks::ArtTraining.check(
      facts(art_trainings: [], online_course_enabled: true, trainings_available: true)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  # Branch: guard -> skip when online course not enabled.
  test "skips when online course is not enabled" do
    result = DashboardTasks::ArtTraining.check(
      facts(art_trainings: [art(Training::PASS)], online_course_enabled: false, trainings_available: true)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  # Branch: guard -> skip when trainings not available.
  test "skips when trainings are not available" do
    result = DashboardTasks::ArtTraining.check(
      facts(art_trainings: [art(Training::PASS)], online_course_enabled: true, trainings_available: false)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  # Branch: STATUS_URGENT when any art is NO_SHOW.
  test "urgent when an art training is a no-show" do
    result = DashboardTasks::ArtTraining.check(
      facts(art_trainings: [art(Training::NO_SHOW)], online_course_enabled: true, trainings_available: true)
    )
    assert_equal DashboardTask::STATUS_URGENT, result.result
    assert_equal "dashboard_arts", result.partial
  end

  # Branch: STATUS_URGENT when any art is FAIL.
  test "urgent when an art training is a fail" do
    result = DashboardTasks::ArtTraining.check(
      facts(art_trainings: [art(Training::FAIL)], online_course_enabled: true, trainings_available: true)
    )
    assert_equal DashboardTask::STATUS_URGENT, result.result
    assert_equal "dashboard_arts", result.partial
  end

  # Branch: STATUS_ACTION_NEEDED when any art is NO_SHIFT (and none urgent).
  test "action needed when an art training has no shift" do
    result = DashboardTasks::ArtTraining.check(
      facts(art_trainings: [art(Training::NO_SHIFT)], online_course_enabled: true, trainings_available: true)
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "dashboard_arts", result.partial
  end

  # Branch: STATUS_WAITING when any art is PENDING (and none urgent/no-shift).
  test "waiting when an art training is pending" do
    result = DashboardTasks::ArtTraining.check(
      facts(art_trainings: [art(Training::PENDING)], online_course_enabled: true, trainings_available: true)
    )
    assert_equal DashboardTask::STATUS_WAITING, result.result
    assert_equal "dashboard_arts", result.partial
  end

  # Branch: STATUS_COMPLETED when no art is urgent/no-shift/pending.
  test "completed when all art trainings are passed" do
    result = DashboardTasks::ArtTraining.check(
      facts(art_trainings: [art(Training::PASS)], online_course_enabled: true, trainings_available: true)
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
    assert_equal "dashboard_arts", result.partial
  end

  # Precedence: urgent wins over no-shift/pending when statuses are mixed.
  test "urgent takes precedence over other statuses" do
    result = DashboardTasks::ArtTraining.check(
      facts(
        art_trainings: [art(Training::PENDING), art(Training::NO_SHIFT), art(Training::FAIL)],
        online_course_enabled: true,
        trainings_available: true
      )
    )
    assert_equal DashboardTask::STATUS_URGENT, result.result
  end

  # Class metadata override.
  test "skip_period covers post and after event" do
    assert_equal [DashboardTask::POST_EVENT, DashboardTask::AFTER_EVENT],
                 DashboardTasks::ArtTraining.skip_period
  end
end
