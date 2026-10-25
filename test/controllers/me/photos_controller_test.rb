# frozen_string_literal: true

require "test_helper"

class Me::PhotosControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    @person = person(:active_ranger)
    sign_in_as(@person)
  end

  # New tests

  test "should get new" do
    get new_me_profile_photo_url
    assert_response :success
  end

  test "new requires authentication" do
    sign_out

    get new_me_profile_photo_url
    assert_redirected_to root_path
  end

  test "new displays upload form" do
    get new_me_profile_photo_url
    assert_response :success

    assert_match /photo|upload/i, response.body
  end

  test "new displays the Take Selfie tab" do
    get new_me_profile_photo_url
    assert_response :success

    assert_select "#tab-camera", text: /Take Selfie/
  end

  # Create tests

  test "create requires photo parameter" do
    post me_profile_photos_url
    assert_response :unprocessable_entity

    json = JSON.parse(response.body)
    # The controller catches ParameterMissing and returns an error
    assert json["error"].present?
  end

  test "create takes a PNG" do
    post me_profile_photos_url, params: { photo: fixture_file_upload("pixel.png", "image/png") }
    assert_response :created
  end

  test "create takes a HEIC sent as application/octet-stream" do
    # Chrome doesn't know HEIC, so that is the type it sends.
    post me_profile_photos_url, params: { photo: fixture_file_upload("pixel.heic", "application/octet-stream") }
    assert_response :created
  end

  test "create refuses a TIFF named and typed as a JPEG" do
    Tempfile.create(%w[tiff .jpg]) do |file|
      Vips::Image.black(8, 8).tiffsave(file.path)
      post me_profile_photos_url, params: { photo: Rack::Test::UploadedFile.new(file.path, "image/jpeg") }
    end
    assert_response :unprocessable_entity
    assert_equal PhotoUploadConcern::PHOTO_TYPE_ERROR, JSON.parse(response.body)["error"]
  end

  test "create refuses an AVIF, which the HEIF decoder opens" do
    post me_profile_photos_url, params: { photo: fixture_file_upload("pixel.avif", "image/avif") }
    assert_response :unprocessable_entity
    assert_equal PhotoUploadConcern::PHOTO_TYPE_ERROR, JSON.parse(response.body)["error"]
  end

  test "create bakes the EXIF orientation into the stored original" do
    require "vips"

    Tempfile.create(%w[portrait .jpg]) do |file|
      # A 40x20 file tagged "rotate 90° to display": a phone portrait shot.
      Vips::Image.black(40, 20)
                 .mutate { |m| m.set_type!(GObject::GINT_TYPE, "orientation", 6) }
                 .write_to_file(file.path)

      post me_profile_photos_url, params: { photo: Rack::Test::UploadedFile.new(file.path, "image/jpeg") }
    end
    assert_response :created

    photo = PersonPhoto.find(JSON.parse(response.body)["id"])
    photo.original.blob.open do |stored|
      image = Vips::Image.new_from_file(stored.path)
      assert_equal [20, 40], [image.width, image.height]
      # The tag is gone or a no-op: auto-rotating the stored file changes nothing
      rotated = Vips::Image.new_from_file(stored.path, autorotate: true)
      assert_equal [20, 40], [rotated.width, rotated.height]
    end
  end

  # Crop tests

  test "crop requires authentication" do
    sign_out

    # Create a photo first
    photo = PersonPhoto.create!(
      person: @person,
      status: PersonPhoto::UPLOADED,
      image_filename: "",
      orig_filename: "",
      profile_filename: ""
    )

    get crop_me_profile_photo_url(photo)
    assert_redirected_to root_path
  end

  test "crop redirects when photo is no longer pending" do
    photo = PersonPhoto.create!(
      person: @person,
      status: PersonPhoto::APPROVED,
      image_filename: "",
      orig_filename: "",
      profile_filename: ""
    )

    get crop_me_profile_photo_url(photo)
    assert_redirected_to me_profile_path
  end

  # Note: Photo destroy tests are complex because they require proper
  # ActiveStorage attachments. These would need integration test setup.
end
