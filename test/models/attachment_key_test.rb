# frozen_string_literal: true

require "test_helper"
require "vips"

# Attachment keys come from the owning model instead of Rails' random token,
# and the file lands under that key on the storage service.
class AttachmentKeyTest < ActiveSupport::TestCase
  include EnvTestHelper
  include PersonPhotoTestHelper

  setup do
    @target = person(:active_ranger)
  end

  test "a photo is stored under photos/ by its filename" do
    # Keys repeat from run to run; a file left behind would pass the check below.
    ActiveStorage::Blob.service.delete("photos/photo-1-uploaded-1.jpg")

    blob = create_photo(original: upload("photo-1-uploaded-1.jpg")).reload.original.blob

    assert_equal "photos/photo-1-uploaded-1.jpg", blob.key
    assert blob.service.exist?(blob.key)
    # The root is tmp/storage, or tmp/storage-<n> in a parallel worker.
    assert_equal File.join(blob.service.root, "photos/photo-1-uploaded-1.jpg"), blob.service.path_for(blob.key)
  end

  test "on the staging server a photo is stored under staging/photos/" do
    with_env("RANGER_CLUBHOUSE_ENVIRONMENT" => "Staging") do
      Current.clear_all # Current reads the deployment once, when it is built

      assert_equal "staging/photos/photo-1-uploaded-1.jpg",
                   PersonPhoto.new(original: upload("photo-1-uploaded-1.jpg")).original.blob.key
    end
  end

  test "a repeated key fails the save" do
    create_photo(original: upload("photo-2-uploaded-1.jpg"))

    assert_raises(ActiveRecord::RecordNotUnique) { create_photo(original: upload("photo-2-uploaded-1.jpg")) }
    assert_equal 1, ActiveStorage::Blob.where(key: "photos/photo-2-uploaded-1.jpg").count
  end

  test "removing an attachment or reusing a stored blob leaves keys alone" do
    photo = create_photo(original: upload("photo-3-uploaded-1.jpg"))

    other = PersonPhoto.new
    other.original = photo.original.blob
    assert_equal "photos/photo-3-uploaded-1.jpg", other.original.blob.key
    assert_nothing_raised { other.original = nil }
  end

  test "a name that is not a has_one_attached is refused" do
    assert_raises(ArgumentError) { PersonPhoto.attachment_key(:person) { |blob| blob.filename.to_s } }
  end

  test "on the training server's frozen clock a second crop still gets its own keys" do
    travel_to Time.zone.local(2026, 10, 15, 12, 0, 0)
    Current.groundhog_day_time = Time.zone.local(2026, 8, 25, 9, 0, 0)
    jpeg = Vips::Image.black(20, 20).write_to_buffer(".jpg")
    photo = create_photo(status: PersonPhoto::UPLOADED, original: upload("photo-4-uploaded-1.jpg", jpeg))

    photo.generate_cropped_attachments!({}, user_id: @target.id)
    first_profile_key = photo.profile.blob.key
    travel 1.second
    photo.generate_cropped_attachments!({}, user_id: @target.id)

    assert_equal "photos/photo-#{@target.id}-#{Time.current.to_i - 1}-profile.jpg", first_profile_key
    assert_equal "photos/photo-#{@target.id}-#{Time.current.to_i}-profile.jpg", photo.profile.blob.key
  end

  private

  def upload(filename, bytes = "not really a jpeg")
    { io: StringIO.new(bytes), filename:, content_type: "image/jpeg" }
  end
end
