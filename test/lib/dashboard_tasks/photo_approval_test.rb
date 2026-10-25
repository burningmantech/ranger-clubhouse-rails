# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::PhotoApprovalTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  def photo(status) = OpenStruct.new(photo_status: status)

  test "approved photo for applicant is completed" do
    result = DashboardTasks::PhotoApproval.check(
      facts(photo: photo(PersonPhoto::APPROVED), is_applicant: true)
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
  end

  test "approved photo for non-applicant is skipped" do
    result = DashboardTasks::PhotoApproval.check(
      facts(photo: photo(PersonPhoto::APPROVED), is_applicant: false)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "submitted photo is waiting with review partial" do
    result = DashboardTasks::PhotoApproval.check(
      facts(photo: photo(PersonPhoto::SUBMITTED))
    )
    assert_equal DashboardTask::STATUS_WAITING, result.result
    assert_equal "photo_approval_review", result.partial
  end

  test "missing photo for applicant is not available with missing partial" do
    result = DashboardTasks::PhotoApproval.check(
      facts(photo: photo(PersonPhoto::MISSING), is_applicant: true)
    )
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "photo_approval_missing", result.partial
  end

  test "missing photo for non-applicant is skipped" do
    result = DashboardTasks::PhotoApproval.check(
      facts(photo: photo(PersonPhoto::MISSING), is_applicant: false)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "nil photo is skipped" do
    result = DashboardTasks::PhotoApproval.check(facts(photo: nil))
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "unknown photo status is skipped" do
    result = DashboardTasks::PhotoApproval.check(
      facts(photo: photo("rejected"))
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "title metadata" do
    assert_equal "Photo Approval", DashboardTasks::PhotoApproval.title
  end
end
