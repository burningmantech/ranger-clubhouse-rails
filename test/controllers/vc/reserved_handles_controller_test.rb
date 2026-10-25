# frozen_string_literal: true

require "test_helper"

class Vc::ReservedHandlesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @vc = person(:echelon_ranger)
    @editor = person(:ranger_with_custom_gender)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "VC")
    ensure_role(Role::EDIT_HANDLE_RESERVATIONS, "Edit Handle Reservations")
    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)
    grant_role(@editor, Role::EDIT_HANDLE_RESERVATIONS)

    @khaki = handle_reservation(:ranger_term)
    @expiring = handle_reservation(:expiring)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "denies access without an authorized role" do
    sign_in_as(@outsider)

    get vc_reserved_handles_path

    assert_redirected_to me_root_path
    assert_equal "Admin, VC, or Edit Handle Reservations role required to view reserved handles.", flash[:error]
  end

  test "vc role gets a read-only list without management buttons" do
    sign_in_as(@vc)

    get vc_reserved_handles_path

    assert_response :success
    assert_match @khaki.handle, response.body
    assert_select "a[href=?]", new_vc_reserved_handle_path, count: 0

    get new_vc_reserved_handle_path

    assert_redirected_to vc_reserved_handles_path
    assert_equal "Admin or Edit Handle Reservations role required to change reserved handles.", flash[:error]
  end

  test "edit handle reservations role alone can manage" do
    sign_in_as(@editor)

    get vc_reserved_handles_path
    assert_response :success

    get new_vc_reserved_handle_path
    assert_response :success

    get edit_vc_reserved_handle_path(@khaki)
    assert_response :success
  end

  test "index filters by type and status" do
    get vc_reserved_handles_path(reservation_type: "slur")

    assert_response :success
    assert_match "Testslur", response.body
    assert_no_match @khaki.handle, response.body

    get vc_reserved_handles_path(status: "expired")

    assert_response :success
    assert_match @expiring.handle, response.body
    assert_no_match @khaki.handle, response.body

    get vc_reserved_handles_path(status: "active")

    assert_response :success
    assert_match @khaki.handle, response.body
    assert_no_match @expiring.handle, response.body
  end

  test "creates a reserved handle" do
    assert_difference "HandleReservation.count", 1 do
      post vc_reserved_handles_path,
           params: { handle_reservation: { handle: "Fresh Handle",
                                           reservation_type: HandleReservation::RESERVATION_TYPE_BRC_TERM,
                                           expires_on: "2030-01-05",
                                           reason: "Testing" } }
    end

    created = HandleReservation.order(:id).last
    assert_redirected_to vc_reserved_handles_path(anchor: "reserved-handle-#{created.id}")
    assert_equal "Reserved handle created.", flash[:success]
    assert_equal Date.new(2030, 1, 5), created.expires_on
    assert_equal "Testing", created.reason
  end

  test "rejects a duplicate handle for the same type" do
    assert_no_difference "HandleReservation.count" do
      post vc_reserved_handles_path,
           params: { handle_reservation: { handle: "KHAKI",
                                           reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM } }
    end

    assert_response :unprocessable_entity
    assert_match "has already been reserved for this type", response.body
  end

  test "a twii entry without a date gets the default expiration" do
    post vc_reserved_handles_path,
         params: { handle_reservation: { handle: "Twii Star",
                                         reservation_type: HandleReservation::RESERVATION_TYPE_TWII_PERSON,
                                         twii_year: "2029" } }

    created = HandleReservation.order(:id).last
    assert_equal HandleReservation.default_twii_expires_on, created.expires_on
    assert_equal 2029, created.twii_year
  end

  test "updates a reserved handle" do
    patch vc_reserved_handle_path(@khaki),
          params: { handle_reservation: { handle: @khaki.handle,
                                          reservation_type: @khaki.reservation_type,
                                          reason: "Uniform color" } }

    assert_redirected_to vc_reserved_handles_path(anchor: "reserved-handle-#{@khaki.id}")
    assert_equal "Reserved handle updated.", flash[:success]
    assert_equal "Uniform color", @khaki.reload.reason
  end

  test "rejects an update that blanks the handle" do
    patch vc_reserved_handle_path(@khaki),
          params: { handle_reservation: { handle: "", reservation_type: @khaki.reservation_type } }

    assert_response :unprocessable_entity
    assert_equal "Khaki", @khaki.reload.handle
  end

  test "deletes a reserved handle" do
    assert_difference "HandleReservation.count", -1 do
      delete vc_reserved_handle_path(@khaki)
    end

    assert_redirected_to vc_reserved_handles_path
    assert_equal "Reserved handle deleted.", flash[:success]
    assert_not HandleReservation.exists?(@khaki.id)
  end

  test "expire deletes expired handles and reports when there are none" do
    post expire_vc_reserved_handles_path

    assert_redirected_to vc_reserved_handles_path
    assert_equal "1 expired handle deleted.", flash[:success]
    assert_not HandleReservation.exists?(@expiring.id)

    post expire_vc_reserved_handles_path

    assert_redirected_to vc_reserved_handles_path
    assert_equal "No handles were found to have expired.", flash[:info]
  end

  test "vc role cannot reach the upload page" do
    sign_in_as(@vc)

    get upload_vc_reserved_handles_path

    assert_redirected_to vc_reserved_handles_path
  end

  test "upload verify reports problems without saving" do
    assert_no_difference "HandleReservation.count" do
      post upload_vc_reserved_handles_path,
           params: { upload: { handles: "Newhandle\nBadline,2027-02-31\nKhaki",
                               reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM } }
    end

    assert_response :unprocessable_entity
    assert_match "2 problems found on lines 2 and 3", response.body
    assert_match "Invalid Date", response.body
    assert_match "has already been reserved for this type", response.body
    assert_select "input[name=?]", "upload[commit]", count: 0
  end

  test "a non-hash upload param is refused like an empty upload rather than raising" do
    assert_no_difference "HandleReservation.count" do
      post upload_vc_reserved_handles_path, params: { upload: "x" }
    end

    assert_response :unprocessable_entity
    assert_match "List at least one handle.", response.body
  end

  test "upload verify reports a handle the pasted list repeats" do
    post upload_vc_reserved_handles_path,
         params: { upload: { handles: "Fresh One\nfresh one",
                             reservation_type: HandleReservation::RESERVATION_TYPE_BRC_TERM } }

    assert_response :unprocessable_entity
    assert_match "1 problem found on line 2", response.body
    assert_match "is listed more than once in this upload", response.body
    assert_select "input[name=?]", "upload[commit]", count: 0
  end

  test "upload verify offers commit when clean, and commit saves" do
    lines = "Fresh One\nFresh Two,2030-01-05,Special reason"

    assert_no_difference "HandleReservation.count" do
      post upload_vc_reserved_handles_path,
           params: { upload: { handles: lines,
                               reservation_type: HandleReservation::RESERVATION_TYPE_BRC_TERM } }
    end

    assert_response :unprocessable_entity
    assert_match "No problems found.", response.body
    assert_match "Commit 2 Handles", response.body
    # The commit form must carry every verified value, or committing posts a
    # blank upload.
    assert_select "input[type=hidden][name=?]", "upload[handles]" do |fields|
      assert_equal lines, fields.first["value"]
    end
    assert_select "input[type=hidden][name=?][value=?]",
                  "upload[reservation_type]", HandleReservation::RESERVATION_TYPE_BRC_TERM
    assert_match "2030-01-05", response.body
    assert_match "Special reason", response.body

    assert_difference "HandleReservation.count", 2 do
      post upload_vc_reserved_handles_path,
           params: { upload: { handles: lines,
                               reservation_type: HandleReservation::RESERVATION_TYPE_BRC_TERM,
                               commit: "1" } }
    end

    assert_redirected_to vc_reserved_handles_path
    assert_equal "2 reserved handles saved.", flash[:success]

    fresh_two = HandleReservation.find_by(handle: "Fresh Two")
    assert_equal Date.new(2030, 1, 5), fresh_two.expires_on
    assert_equal "Special reason", fresh_two.reason
    assert_equal HandleReservation::RESERVATION_TYPE_BRC_TERM, fresh_two.reservation_type
  end

  test "upload verify shows the default twii expiration" do
    post upload_vc_reserved_handles_path,
         params: { upload: { handles: "Twii Star",
                             reservation_type: HandleReservation::RESERVATION_TYPE_TWII_PERSON,
                             twii_year: "2029" } }

    assert_response :unprocessable_entity
    assert_match HandleReservation.default_twii_expires_on.to_s, response.body
  end

  test "commit keeps saving good rows and reports the ones that failed" do
    assert_difference "HandleReservation.count", 1 do
      post upload_vc_reserved_handles_path,
           params: { upload: { handles: "Fresh Three\nKhaki",
                               reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM,
                               commit: "1" } }
    end

    assert_response :unprocessable_entity
    assert_match "1 of 2 handles could not be saved.", response.body
    assert_match "has already been reserved for this type", response.body
    assert HandleReservation.exists?(handle: "Fresh Three")

    # Only the line that still needs fixing is left to verify again.
    assert_select "textarea#upload_handles", text: "Khaki"
  end

  test "upload rejects a submission without handles" do
    post upload_vc_reserved_handles_path,
         params: { upload: { handles: "", reservation_type: HandleReservation::RESERVATION_TYPE_BRC_TERM } }

    assert_response :unprocessable_entity
    assert_match "List at least one handle.", response.body
  end
end
