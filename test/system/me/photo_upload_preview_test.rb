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

  # A proxy or a captive portal can answer the upload with a page of its own,
  # status 200: the box shows request.js's message, not a crash in the visit.
  test "an answer that is not JSON is reported, not followed" do
    visit new_me_profile_photo_path
    execute_script(<<~JS)
      window.fetch = () => Promise.resolve(new Response("<html></html>", { status: 200, headers: { "Content-Type": "text/html" } }))
    JS
    attach_file "photo-dropzone", file_fixture("pixel.png").to_s, make_visible: true
    find("[data-photo-upload-target=submitButton]").click

    assert_selector "[data-photo-upload-target=error]", text: /Expected a JSON response/
  end
end
