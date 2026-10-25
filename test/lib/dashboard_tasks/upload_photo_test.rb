# frozen_string_literal: true

require "test_helper"
require "ostruct"

class DashboardTasks::UploadPhotoTest < ActiveSupport::TestCase
  def facts(**overrides) = DashboardFacts.new(**overrides)

  def photo(status:, upload_enabled: true)
    OpenStruct.new(photo_status: status, upload_enabled: upload_enabled)
  end

  test "immediate metadata is true" do
    assert DashboardTasks::UploadPhoto.immediate
  end

  test "rejected photo is urgent and immediate" do
    result = DashboardTasks::UploadPhoto.check(facts(photo: photo(status: PersonPhoto::REJECTED)))
    assert_equal DashboardTask::STATUS_URGENT, result.result
    assert_equal "upload_photo_rejected", result.partial
    assert result.immediate
  end

  test "missing photo with upload disabled is waiting" do
    result = DashboardTasks::UploadPhoto.check(
      facts(photo: photo(status: PersonPhoto::MISSING, upload_enabled: false))
    )
    assert_equal DashboardTask::STATUS_WAITING, result.result
    assert_equal "upload_photo_disabled", result.partial
  end

  test "missing photo with upload enabled needs action" do
    result = DashboardTasks::UploadPhoto.check(
      facts(photo: photo(status: PersonPhoto::MISSING, upload_enabled: true))
    )
    assert_equal DashboardTask::STATUS_ACTION_NEEDED, result.result
    assert_equal "upload_photo_action", result.partial
  end

  test "submitted photo for applicant is completed" do
    result = DashboardTasks::UploadPhoto.check(
      facts(photo: photo(status: PersonPhoto::SUBMITTED), is_applicant: true)
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
  end

  test "submitted photo for non-applicant is skipped" do
    result = DashboardTasks::UploadPhoto.check(
      facts(photo: photo(status: PersonPhoto::SUBMITTED), is_applicant: false)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "approved photo for applicant is completed" do
    result = DashboardTasks::UploadPhoto.check(
      facts(photo: photo(status: PersonPhoto::APPROVED), is_applicant: true)
    )
    assert_equal DashboardTask::STATUS_COMPLETED, result.result
  end

  test "approved photo for non-applicant is skipped" do
    result = DashboardTasks::UploadPhoto.check(
      facts(photo: photo(status: PersonPhoto::APPROVED), is_applicant: false)
    )
    assert_equal DashboardTask::STATUS_SKIP, result.result
  end

  test "unknown photo status is not available" do
    result = DashboardTasks::UploadPhoto.check(facts(photo: photo(status: "unexpected")))
    assert_equal DashboardTask::STATUS_NOT_AVAILABLE, result.result
    assert_equal "upload_photo_error", result.partial
  end
end
