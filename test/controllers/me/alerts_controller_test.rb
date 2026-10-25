# frozen_string_literal: true

require "test_helper"

class Me::AlertsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include DomIdTestHelper # assert_unique_dom_ids

  setup do
    @person = person(:active_ranger)
    sign_in_as(@person)
  end

  # =========================================================================
  # Edit tests
  # =========================================================================

  test "edit requires authentication" do
    sign_out

    get edit_me_alerts_url
    assert_redirected_to root_path
  end

  test "edit loads successfully" do
    get edit_me_alerts_url
    assert_response :success
  end

  test "edit shows verification section when number is unverified" do
    @person.update_columns(sms_number: "+15551234567", sms_verified: false, sms_stopped: false)

    get edit_me_alerts_url
    assert_response :success
    assert_match(/Verify Your Number/, response.body)
  end

  test "edit names the sms fields inside the person scope the controller reads" do
    @person.update_columns(sms_number: "+15551234567", sms_verified: false, sms_stopped: false)

    get edit_me_alerts_url

    assert_response :success
    assert_select "input[name=?]", "person[sms_number]"
    assert_select "input[name=?]", "person[verification_code]"
  end

  test "edit gives every form its own intent field without repeating an id" do
    @person.update_columns(sms_number: "+15551234567", sms_verified: false, sms_stopped: false)

    get edit_me_alerts_url

    assert_response :success
    assert_select "input[type=hidden][name=intent]", minimum: 2
    assert_unique_dom_ids
  end

  test "edit shows stopped warning when number is stopped" do
    @person.update_columns(sms_number: "+15551234567", sms_stopped: true)

    get edit_me_alerts_url
    assert_response :success
    assert_match(/Stopped/, response.body)
  end

  # =========================================================================
  # Intent: save_preferences
  # =========================================================================

  test "save_preferences updates alert preferences" do
    alert = alert(:shift_change)

    # Ensure a preference record exists with known values
    ap = PersonAlert.find_or_create_by!(person_id: @person.id, alert_id: alert.id)
    ap.update_columns(use_email: true, use_sms: true)

    patch me_alerts_url, params: {
      intent: "save_preferences",
      alerts: { "0" => { id: alert.id, use_email: "0", use_sms: "0" } }
    }

    assert_redirected_to edit_me_alerts_path
    assert_equal "Alert preferences updated.", flash[:success]

    ap.reload
    assert_not ap.use_email
    assert_not ap.use_sms
  end

  test "save_preferences creates PersonAlert record if none exists" do
    alert = alert(:ranger_contact)

    # Ensure no pref exists
    PersonAlert.where(person_id: @person.id, alert_id: alert.id).delete_all

    assert_difference("PersonAlert.count", 1) do
      patch me_alerts_url, params: {
        intent: "save_preferences",
        alerts: { "0" => { id: alert.id, use_email: "1", use_sms: "0" } }
      }
    end

    assert_redirected_to edit_me_alerts_path
  end

  test "save_preferences drops rows that are not hashes rather than raising" do
    alert = alert(:shift_change)
    ap = PersonAlert.find_or_create_by!(person_id: @person.id, alert_id: alert.id)
    ap.update_columns(use_email: true, use_sms: true)

    patch me_alerts_url, params: { intent: "save_preferences", alerts: "x" }
    assert_redirected_to edit_me_alerts_path

    patch me_alerts_url, params: {
      intent: "save_preferences",
      alerts: { "0" => "x", "1" => { id: alert.id, use_email: "0", use_sms: "1" } }
    }
    assert_redirected_to edit_me_alerts_path
    assert_not ap.reload.use_email
  end

  test "save_preferences skips invalid alert IDs" do
    patch me_alerts_url, params: {
      intent: "save_preferences",
      alerts: { "0" => { id: 99999, use_email: "1", use_sms: "1" } }
    }

    assert_redirected_to edit_me_alerts_path
  end

  # =========================================================================
  # Intent: save_number
  # =========================================================================

  test "save_number clears phone number when blank" do
    @person.update_columns(sms_number: "+15551234567", sms_verified: true)

    patch me_alerts_url, params: {
      intent: "save_number",
      person: { sms_number: "" }
    }

    assert_redirected_to edit_me_alerts_path
    assert_match(/removed/, flash[:success])

    @person.reload
    assert_nil @person.sms_number
    assert_not @person.sms_verified?
  end

  test "save_number with a non-hash person param is refused rather than clearing the number" do
    @person.update_columns(sms_number: "+15551234567", sms_verified: true)

    patch me_alerts_url, params: { intent: "save_number", person: "x" }

    assert_response :bad_request
    assert_equal "+15551234567", @person.reload.sms_number
  end

  test "save_number saves a new phone number and starts verification" do
    @person.update_columns(sms_number: nil, sms_code: nil, sms_verified: false)

    patch me_alerts_url, params: {
      intent: "save_number",
      person: { sms_number: "+12025551234" }
    }

    assert_redirected_to edit_me_alerts_path

    @person.reload
    assert_equal "+12025551234", @person.sms_number
    assert @person.sms_code.present?
    assert_not @person.sms_verified?
  end

  test "save_number rejects invalid phone number" do
    patch me_alerts_url, params: {
      intent: "save_number",
      person: { sms_number: "abc" }
    }

    assert_response :unprocessable_entity
    assert_match(/does not appear to be valid/, flash[:error])
  end

  test "save_number rejects duplicate phone number" do
    other_person = person(:inactive_ranger)
    other_person.update_columns(sms_number: "+12025551234")

    patch me_alerts_url, params: {
      intent: "save_number",
      person: { sms_number: "+12025551234" }
    }

    assert_response :unprocessable_entity
    assert_match(/already used/, flash[:error])
  end

  # =========================================================================
  # Intent: confirm_code
  # =========================================================================

  test "confirm_code verifies phone with correct code" do
    @person.update_columns(sms_number: "+15551234567", sms_code: "1234", sms_verified: false)

    patch me_alerts_url, params: {
      intent: "confirm_code",
      person: { verification_code: "1234" }
    }

    assert_redirected_to edit_me_alerts_path
    assert_match(/verified/, flash[:success])

    @person.reload
    assert @person.sms_verified?
  end

  test "confirm_code rejects wrong code" do
    @person.update_columns(sms_number: "+15551234567", sms_code: "1234", sms_verified: false)

    patch me_alerts_url, params: {
      intent: "confirm_code",
      person: { verification_code: "9999" }
    }

    assert_response :unprocessable_entity
    assert_match(/does not match/, flash[:error])
  end

  test "confirm_code with a non-hash person param is refused like a wrong code rather than raising" do
    @person.update_columns(sms_number: "+15551234567", sms_code: "1234", sms_verified: false)

    patch me_alerts_url, params: { intent: "confirm_code", person: "x" }

    assert_response :unprocessable_entity
    assert_match(/does not match/, flash[:error])
    assert_not @person.reload.sms_verified?
  end

  test "confirm_code handles already verified" do
    @person.update_columns(sms_number: "+15551234567", sms_verified: true)

    patch me_alerts_url, params: {
      intent: "confirm_code",
      person: { verification_code: "1234" }
    }

    assert_redirected_to edit_me_alerts_path
    assert_match(/already verified/, flash[:info])
  end

  # =========================================================================
  # Intent: send_code
  # =========================================================================

  test "send_code refuses when already verified" do
    @person.update_columns(sms_number: "+15551234567", sms_verified: true)

    patch me_alerts_url, params: { intent: "send_code" }

    assert_redirected_to edit_me_alerts_path
    assert_match(/already verified/, flash[:info])
  end

  test "send_code refuses when no number on file" do
    @person.update_columns(sms_number: nil)

    patch me_alerts_url, params: { intent: "send_code" }

    assert_redirected_to edit_me_alerts_path
    assert_match(/No phone number/, flash[:error])
  end

  # =========================================================================
  # Intent: save_sms_state (admin only)
  # =========================================================================

  test "save_sms_state is forbidden for self-service and changes no columns" do
    @person.update_columns(sms_number: "+15551234567", sms_stopped: false, sms_verified: false)
    # Every signed-in request stamps last_seen_at (ApplicationController#set_current_user).
    before = @person.reload.attributes.except("last_seen_at")

    patch me_alerts_url, params: {
      intent: "save_sms_state",
      person: { sms_number: "+12025559876", sms_stopped: "1", sms_verified: "1" }
    }

    assert_response :forbidden
    assert_equal before, @person.reload.attributes.except("last_seen_at")
  end

  # =========================================================================
  # Unknown intent
  # =========================================================================

  test "unknown intent shows error" do
    patch me_alerts_url, params: { intent: "bogus" }

    assert_redirected_to edit_me_alerts_path
    assert_match(/Unknown action/, flash[:error])
  end

  # =========================================================================
  # Authentication
  # =========================================================================

  test "update requires authentication" do
    sign_out

    patch me_alerts_url, params: {
      intent: "save_preferences",
      alerts: { "0" => { id: 1, use_email: "1", use_sms: "1" } }
    }

    assert_redirected_to root_path
  end
end
