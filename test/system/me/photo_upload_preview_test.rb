# frozen_string_literal: true

require "application_system_test_case"

class Me::PhotoUploadPreviewTest < ApplicationSystemTestCase
  setup do
    sign_in(person(:active_ranger))
  end

  # Chrome and Firefox can't decode HEIC, so the thumbnail <img> fires error
  # instead of load. A text file with an image extension takes the same path
  # without a 2 MB fixture.
  test "an undecodable file shows the placeholder instead of a broken thumbnail" do
    visit new_me_profile_photo_path

    attach_file "photo-dropzone", file_fixture("pixel.png").to_s, make_visible: true
    assert_selector "[data-photo-upload-target=preview] img"
    assert_no_selector "[data-photo-upload-target=previewFallback]"

    attach_file "photo-dropzone", file_fixture("undecodable.png").to_s, make_visible: true
    assert_selector "[data-photo-upload-target=previewFallback]"
    assert_text "Your browser can't show a preview of this file type."
    assert_no_selector "[data-photo-upload-target=preview] img"
  end
end
