# frozen_string_literal: true

require "test_helper"

class Vc::PhotosControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include PersonPhotoTestHelper

  setup do
    setup_photo_people_and_roles
  end

  test "admin can view the photo listing" do
    photo = create_photo
    sign_in_as(@admin)
    get vc_photos_path
    assert_response :success
    assert_match @target.callsign, response.body
    assert_match vc_photos_review_info_path(photo), response.body
  end

  test "vc can view the photo listing" do
    sign_in_as(@vc)
    get vc_photos_path
    assert_response :success
  end

  test "event management cannot view the photo listing" do
    sign_in_as(@em)
    get vc_photos_path
    assert_redirected_to me_root_path
  end

  test "listing shows the empty state when no photos exist" do
    sign_in_as(@vc)
    get vc_photos_path
    assert_response :success
    assert_match "No photos have been uploaded", response.body
  end

  test "listing paginates past the page size" do
    now = Time.current
    PersonPhoto.insert_all(
      Array.new(101) do
        { person_id: @target.id, status: PersonPhoto::SUBMITTED,
          image_filename: "", orig_filename: "", created_at: now, updated_at: now }
      end
    )

    sign_in_as(@vc)
    get vc_photos_path
    assert_response :success
    assert_match "Page 1 of 2 · 101 photos", response.body
    # Above the table and below it. A button with no page to go to is drawn
    # disabled, so only a link says the page is there.
    assert_select "a[href=?]", vc_photos_path(page: 2), text: "Next Page", count: 2

    get vc_photos_path(page: 2)
    assert_response :success
    assert_match "Page 2 of 2 · 101 photos", response.body
    assert_select "a[href=?]", vc_photos_path(page: 1), text: "Previous Page", count: 2
  end

  # The thumbnail links open Vc::PhotosReviewController#info. That endpoint must
  # keep serving non-pending photos (approved, rejected) for this page's sake.
  test "info modal renders for an approved photo" do
    photo = create_photo(status: PersonPhoto::APPROVED)
    sign_in_as(@vc)
    get vc_photos_review_info_path(photo)
    assert_response :success
    assert_match "Photo Information", response.body
  end

  test "garbage and out-of-range page params do not error" do
    create_photo
    sign_in_as(@vc)

    get vc_photos_path(page: "banana")
    assert_response :success

    get vc_photos_path(page: 99)
    assert_response :success
    assert_match "Page 99 of 1", response.body
  end
end
