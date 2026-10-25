# frozen_string_literal: true

require "test_helper"

class PhotoPendingJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
    PersonPhoto.delete_all
    @person = person(:active_ranger)
  end

  test "perform mails the reviewers about photos waiting for them" do
    create_photo(PersonPhoto::SUBMITTED)

    assert_emails 1 do
      PhotoPendingJob.perform_now
    end

    mail = ActionMailer::Base.deliveries.last

    assert_equal [EmailAddresses::VOLUNTEER_COORDINATORS_TEAM], mail.to
    assert_includes mail.body.to_s, @person.callsign
    assert_includes mail.body.to_s, %(href="http://example.com/vc/photos-review")
  end

  test "perform sends nothing when no photo is waiting" do
    create_photo(PersonPhoto::APPROVED)

    assert_emails 0 do
      PhotoPendingJob.perform_now
    end
  end

  private

  def create_photo(status)
    PersonPhoto.create!(person: @person, status: status, image_filename: "", orig_filename: "", profile_filename: "")
  end
end
