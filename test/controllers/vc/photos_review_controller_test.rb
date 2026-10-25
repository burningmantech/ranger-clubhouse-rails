# frozen_string_literal: true

require "test_helper"

class Vc::PhotosReviewControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include PersonPhotoTestHelper
  include EmailSuppressionTestHelper

  setup do
    setup_photo_people_and_roles
  end

  # Index

  test "admin can view the review queue" do
    photo = create_photo
    sign_in_as(@admin)
    get vc_photos_review_path
    assert_response :success
    assert_match @target.callsign, response.body
    assert_match vc_photos_review_approve_path(photo), response.body
  end

  test "vc can view the review queue" do
    sign_in_as(@vc)
    get vc_photos_review_path
    assert_response :success
  end

  test "event management cannot view the review queue" do
    sign_in_as(@em)
    get vc_photos_review_path
    assert_redirected_to me_root_path
  end

  test "queue shows the all-reviewed message when empty" do
    sign_in_as(@vc)
    get vc_photos_review_path
    assert_response :success
    assert_match "All photos have been reviewed", response.body
  end

  test "queue links prior rejected photos to the info dialog" do
    create_photo
    reject = create_photo(status: PersonPhoto::REJECTED)
    sign_in_as(@vc)
    get vc_photos_review_path
    assert_response :success
    assert_match vc_photos_review_info_path(reject), response.body
  end

  # Approve

  test "approve marks the photo reviewed and emails the volunteer" do
    photo = create_photo
    sign_in_as(@vc)

    assert_emails 1 do
      patch vc_photos_review_approve_path(photo)
    end
    assert_redirected_to vc_photos_review_path

    photo.reload
    assert_equal PersonPhoto::APPROVED, photo.status
    assert_not_nil photo.reviewed_at
    assert_equal @vc.id, photo.review_person_id

    log = MailLog.where(person_id: @target.id).last
    assert log, "expected a MailLog record"
    assert_match "APPROVED", log.subject
    assert ActionLog.exists?(event: "person-photo-review", target_person_id: @target.id)
  end

  test "approve makes the photo current and archives the person's other photos" do
    old_approved = create_photo(status: PersonPhoto::APPROVED)
    rejected = create_photo(status: PersonPhoto::REJECTED)
    photo = create_photo
    other_person_photo = create_photo(person: @em, status: PersonPhoto::REJECTED)
    sign_in_as(@vc)

    patch vc_photos_review_approve_path(photo)

    assert_equal PersonPhoto::APPROVED, photo.reload.status
    assert_equal PersonPhoto::ARCHIVED, old_approved.reload.status, "prior approved photo should be archived"
    assert PersonPhoto.exists?(other_person_photo.id), "other people's photos must be untouched"
    assert_equal photo.id, @target.reload.photo&.id, "approved photo should become the current photo"
  end

  test "current photo is the most recent approved photo" do
    older = create_photo(status: PersonPhoto::APPROVED)
    newer = create_photo
    # Bypass callbacks to simulate legacy data with two approved photos.
    newer.update_columns(status: PersonPhoto::APPROVED, created_at: older.created_at + 1.minute)

    assert_equal newer.id, @target.reload.photo.id
  end

  test "approve does not email a locked account" do
    @target.update_column(:status, Person::SUSPENDED)
    photo = create_photo
    sign_in_as(@vc)

    assert_emails 0 do
      patch vc_photos_review_approve_path(photo)
    end
    assert_equal PersonPhoto::APPROVED, photo.reload.status
  end

  # SuppressedRecipientsInterceptor holds an email left with nobody to send to,
  # so it gets no mail log row either.
  test "approve saves but emails nobody when the volunteer's address is suppressed" do
    suppress_email(@target.email)
    photo = create_photo
    sign_in_as(@vc)

    assert_no_emails do
      assert_no_difference "MailLog.count" do
        patch vc_photos_review_approve_path(photo)
      end
    end
    assert_redirected_to vc_photos_review_path
    assert_equal PersonPhoto::APPROVED, photo.reload.status
    assert ActionLog.exists?(event: "email-suppressed", target_person_id: @target.id)
  end

  # Reject

  test "reject records reasons and message and emails the volunteer" do
    photo = create_photo
    sign_in_as(@vc)

    assert_emails 1 do
      patch vc_photos_review_reject_path(photo), params: {
        person_photo: { reject_reasons: %w[blurry too-close], reject_message: "Please retake outdoors." }
      }
    end
    assert_redirected_to vc_photos_review_path

    photo.reload
    assert_equal PersonPhoto::REJECTED, photo.status
    assert_equal %w[blurry too-close], photo.reject_reasons
    assert_equal "Please retake outdoors.", photo.reject_message
    assert_equal @vc.id, photo.review_person_id

    mail = ActionMailer::Base.deliveries.last
    assert_match "Retake the photo and make sure things are in focus", mail.body.decoded
    assert_match "Please retake outdoors.", mail.body.decoded
    assert_includes mail.body.decoded, %(<a href="http://example.com/">Ranger Secret Clubhouse</a>)
  end

  test "reject without reasons leaves the photo submitted" do
    photo = create_photo
    sign_in_as(@vc)

    assert_emails 0 do
      patch vc_photos_review_reject_path(photo), params: { person_photo: { reject_message: "nope" } }
    end
    assert_redirected_to vc_photos_review_path
    assert_equal PersonPhoto::SUBMITTED, photo.reload.status
  end

  test "a non-hash person_photo param is read as no reasons rather than raising" do
    photo = create_photo
    sign_in_as(@vc)

    assert_emails 0 do
      patch vc_photos_review_reject_path(photo), params: { person_photo: "x" }
    end
    assert_redirected_to vc_photos_review_path
    assert_equal PersonPhoto::SUBMITTED, photo.reload.status

    get vc_photos_review_reject_preview_path(photo), params: { person_photo: "x" }
    assert_response :success
  end

  test "unknown rejection reasons are discarded" do
    photo = create_photo
    sign_in_as(@vc)

    patch vc_photos_review_reject_path(photo), params: {
      person_photo: { reject_reasons: %w[blurry bogus-reason] }
    }
    assert_equal %w[blurry], photo.reload.reject_reasons
  end

  test "approve over turbo stream keeps the approved card on the page" do
    photo = create_photo
    sign_in_as(@vc)

    patch vc_photos_review_approve_path(photo), as: :turbo_stream
    assert_response :success
    assert_equal PersonPhoto::APPROVED, photo.reload.status
    assert_select "turbo-stream[action=?][target=?]", "replace", ActionView::RecordIdentifier.dom_id(photo)
    assert_match vc_photos_review_reject_dialog_path(photo), response.body
    assert_no_match vc_photos_review_approve_path(photo), response.body
    assert_no_match vc_photos_review_crop_path(photo), response.body
  end

  test "reject over turbo stream keeps the rejected card on the page" do
    photo = create_photo
    sign_in_as(@vc)

    patch vc_photos_review_reject_path(photo), params: { person_photo: { reject_reasons: %w[blurry] } },
                                               as: :turbo_stream
    assert_response :success
    assert_equal PersonPhoto::REJECTED, photo.reload.status
    assert_select "turbo-stream[action=?][target=?]", "replace", ActionView::RecordIdentifier.dom_id(photo)
    assert_select "turbo-stream[action=?][target=?]", "update", "modal"
    assert_match PersonPhoto::REJECTIONS[:blurry][:label], response.body
    assert_match vc_photos_review_approve_path(photo), response.body
    assert_no_match vc_photos_review_reject_dialog_path(photo), response.body
  end

  test "reject over turbo stream without reasons only reports the error" do
    photo = create_photo
    sign_in_as(@vc)

    patch vc_photos_review_reject_path(photo), params: { person_photo: { reject_message: "nope" } }, as: :turbo_stream
    assert_response :success
    assert_equal PersonPhoto::SUBMITTED, photo.reload.status
    assert_match "Mark one or more reasons", response.body
    assert_select "turbo-stream[action=?]", "replace", count: 0
  end

  # Dialogs and preview

  test "reject dialog renders" do
    photo = create_photo
    sign_in_as(@vc)
    get vc_photos_review_reject_dialog_path(photo)
    assert_response :success
    assert_match "Reject Photo for #{@target.callsign}", response.body
  end

  test "info dialog renders" do
    photo = create_photo(status: PersonPhoto::REJECTED, reject_reasons: %w[blurry])
    sign_in_as(@vc)
    get vc_photos_review_info_path(photo)
    assert_response :success
    assert_match PersonPhoto::REJECTIONS[:blurry][:label], response.body
  end

  test "reject preview renders the rejection email" do
    photo = create_photo
    sign_in_as(@vc)
    get vc_photos_review_reject_preview_path(photo), params: {
      person_photo: { reject_reasons: %w[blurry], reject_message: "Try again" }
    }
    assert_response :success
    assert_match "Retake the photo and make sure things are in focus", response.body
    assert_match "Try again", response.body
  end

  # Crop (edit) flow

  test "crop page renders for a submitted photo" do
    photo = create_photo
    photo.original.attach(io: StringIO.new("fake image data"), filename: "photo.jpg", content_type: "image/jpeg")
    sign_in_as(@vc)
    get vc_photos_review_crop_path(photo)
    assert_response :success
    assert_match "Photo Review", response.body
    assert_select "a[href=?]", vc_photos_review_path, text: "Cancel"
    assert_no_match "Delete this photo?", response.body
  end

  test "crop redirects back to the queue for a non-pending photo" do
    photo = create_photo(status: PersonPhoto::APPROVED)
    sign_in_as(@vc)
    get vc_photos_review_crop_path(photo)
    assert_redirected_to vc_photos_review_path
  end

  test "destroy removes a pending photo and returns to the queue" do
    photo = create_photo
    sign_in_as(@vc)
    delete vc_photos_review_photo_path(photo)
    assert_redirected_to vc_photos_review_path
    assert_not PersonPhoto.exists?(photo.id)
  end

  test "event management cannot approve" do
    photo = create_photo
    sign_in_as(@em)
    patch vc_photos_review_approve_path(photo)
    assert_redirected_to me_root_path
    assert_equal PersonPhoto::SUBMITTED, photo.reload.status
  end
end
