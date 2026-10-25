# frozen_string_literal: true

require "test_helper"
require "vips"

# Superseded and deleted photo files must leave the storage service: a re-crop
# replaces the profile and avatar blobs, and destroying a photo drops all three.
class PersonPhotoPurgeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  IDENTITY_CROP = {
    scale_x: 1.0, skew_x: 0.0, skew_y: 0.0, scale_y: 1.0, translate_x: 0.0, translate_y: 0.0
  }.freeze

  setup do
    @person = person(:active_ranger)
    @photo = PersonPhoto.create!(person: @person, status: PersonPhoto::UPLOADED,
                                 image_filename: "", orig_filename: "", profile_filename: "")
    jpeg = Vips::Image.black(20, 20).write_to_buffer(".jpg")
    @photo.original.attach(io: StringIO.new(jpeg), filename: "original.jpg", content_type: "image/jpeg")
    @photo.generate_default_attachments!(user_id: @person.id)
  end

  test "a re-crop purges the superseded profile and avatar blobs" do
    old_profile = @photo.profile.blob
    old_avatar = @photo.avatar.blob

    # The filename is the storage key and carries the second, so a re-crop in
    # the same second as the first crop would collide with the blob awaiting purge.
    travel 1.second do
      assert_enqueued_with(job: ActiveStorage::PurgeJob, args: [old_profile]) do
        assert_enqueued_with(job: ActiveStorage::PurgeJob, args: [old_avatar]) do
          @photo.generate_cropped_attachments!(IDENTITY_CROP, user_id: @person.id)
        end
      end
    end

    assert_not_equal old_profile.id, @photo.profile.blob.id
    assert_not_equal old_avatar.id, @photo.avatar.blob.id
  end

  test "destroying a photo purges its original, profile and avatar blobs" do
    blobs = [@photo.original.blob, @photo.profile.blob, @photo.avatar.blob]

    assert_enqueued_jobs 3, only: ActiveStorage::PurgeJob do
      @photo.destroy!
    end
    blobs.each { |blob| assert_enqueued_with(job: ActiveStorage::PurgeJob, args: [blob]) }
  end

  test "delete_pending purges the other pending photos' blobs" do
    keeper = PersonPhoto.create!(person: @person, status: PersonPhoto::SUBMITTED,
                                 image_filename: "", orig_filename: "", profile_filename: "")

    assert_enqueued_jobs 3, only: ActiveStorage::PurgeJob do
      PersonPhoto.delete_pending(@person.id, keeper.id)
    end
    assert_not PersonPhoto.exists?(@photo.id)
    assert_equal 0, ActiveStorage::Attachment.where(record: @photo).count
  end
end
