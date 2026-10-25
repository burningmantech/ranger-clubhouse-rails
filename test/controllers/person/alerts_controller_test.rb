# frozen_string_literal: true

require "test_helper"

class Person::AlertsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    Rails.cache.clear

    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @vc = person(:echelon_ranger)
    @no_one = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")

    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)
  end

  def ninja_admin
    @ninja_admin ||= begin
                       person = person(:alpha_ranger)
                       grant_role(person, Role::ADMIN)
                       grant_role(person, Role::TECH_NINJA)
                       person
                     end
  end

  teardown do
    Rails.cache.clear
  end

  # =========================================================================
  # Authorization
  # =========================================================================

  test "edit requires authentication" do
    get edit_person_alerts_url(@target)
    assert_redirected_to root_path
  end

  test "admin can GET edit for any person" do
    sign_in_as(@admin)
    get edit_person_alerts_url(@target)
    assert_response :success
  end

  test "vc cannot GET edit (admin only)" do
    sign_in_as(@vc)
    get edit_person_alerts_url(@target)
    assert_redirected_to me_root_path
  end

  test "non-admin user cannot GET edit" do
    sign_in_as(@no_one)
    get edit_person_alerts_url(@target)
    assert_redirected_to me_root_path
  end

  # =========================================================================
  # Edit page content
  # =========================================================================

  test "admin edit page shows target callsign and hides SMS phone management" do
    sign_in_as(@admin)
    get edit_person_alerts_url(@target)
    assert_response :success
    assert_match(/Alert Preferences for #{Regexp.escape(@target.callsign)}/, response.body)
    assert_no_match(/SMS Phone Number/, response.body)
    assert_no_match(/Verify Your Number/, response.body)
  end

  # =========================================================================
  # save_preferences (the only allowed intent for admin)
  # =========================================================================

  test "admin can save_preferences for target" do
    sign_in_as(@admin)
    alert = alert(:shift_change)

    ap = PersonAlert.find_or_create_by!(person_id: @target.id, alert_id: alert.id)
    ap.update_columns(use_email: true, use_sms: true)

    patch person_alerts_url(@target), params: {
      intent: "save_preferences",
      alerts: { "0" => { id: alert.id, use_email: "0", use_sms: "0" } }
    }

    assert_redirected_to edit_person_alerts_path(@target)
    assert_equal "Alert preferences updated.", flash[:success]

    ap.reload
    assert_not ap.use_email
    assert_not ap.use_sms
  end

  test "save_preferences logs the change with the admin as actor" do
    sign_in_as(@admin)
    alert = alert(:shift_change)

    ap = PersonAlert.find_or_create_by!(person_id: @target.id, alert_id: alert.id)
    ap.update_columns(use_email: true, use_sms: true)

    assert_difference("ActionLog.where(event: 'person-alerts-update').count", 1) do
      patch person_alerts_url(@target), params: {
        intent: "save_preferences",
        alerts: { "0" => { id: alert.id, use_email: "0", use_sms: "1" } }
      }
    end

    log = ActionLog.where(event: "person-alerts-update").last
    assert_equal @admin.id, log.person_id
    assert_includes log.message, @target.callsign
  end

  # =========================================================================
  # Other intents are forbidden for admin
  # =========================================================================

  test "save_number is forbidden for admin" do
    sign_in_as(@admin)
    patch person_alerts_url(@target), params: {
      intent: "save_number",
      person: { sms_number: "+15551234567" }
    }
    assert_response :forbidden
  end

  test "send_code is forbidden for admin" do
    sign_in_as(@admin)
    patch person_alerts_url(@target), params: { intent: "send_code" }
    assert_response :forbidden
  end

  test "confirm_code is forbidden for admin" do
    sign_in_as(@admin)
    patch person_alerts_url(@target), params: {
      intent: "confirm_code",
      person: { verification_code: "1234" }
    }
    assert_response :forbidden
  end

  # =========================================================================
  # SMS state — read-only for admin, editable for tech-ninja
  # =========================================================================

  test "admin (no tech-ninja) sees read-only SMS state on edit page" do
    @target.update_columns(sms_number: "+15551234567", sms_stopped: true, sms_verified: false)

    sign_in_as(@admin)
    get edit_person_alerts_url(@target)
    assert_response :success

    assert_match(/SMS State/, response.body)
    assert_match(/\+15551234567/, response.body)
    assert_no_match(/name="person\[sms_code\]"/, response.body)
    assert_no_match(/name="person\[sms_stopped\]"/, response.body)
  end

  test "tech-ninja sees editable SMS state inputs on edit page" do
    sign_in_as(ninja_admin)
    get edit_person_alerts_url(@target)
    assert_response :success

    assert_match(/SMS State/, response.body)
    assert_match(/name="person\[sms_number\]"/, response.body)
    assert_match(/name="person\[sms_stopped\]"/, response.body)
    assert_match(/name="person\[sms_verified\]"/, response.body)
  end

  test "save_sms_state is forbidden for admin without tech-ninja" do
    @target.update_columns(sms_code: "1234", sms_stopped: false, sms_verified: false)

    sign_in_as(@admin)
    patch person_alerts_url(@target), params: {
      intent: "save_sms_state",
      person: { sms_code: "9999", sms_stopped: "1", sms_verified: "1" }
    }
    assert_response :forbidden

    @target.reload
    assert_equal "1234", @target.sms_code
    assert_not @target.sms_stopped?
    assert_not @target.sms_verified?
  end

  test "save_sms_state updates target columns and logs for tech-ninja" do
    @target.update_columns(sms_number: "+15550001234", sms_stopped: false, sms_verified: false)

    sign_in_as(ninja_admin)

    patch person_alerts_url(@target), params: {
      intent: "save_sms_state",
      person: { sms_number: "+15550001234", sms_stopped: "1", sms_verified: "1" }
    }

    assert_redirected_to edit_person_alerts_path(@target)
    assert_equal "SMS state updated.", flash[:success]

    @target.reload
    assert_equal "+15550001234", @target.sms_number
    assert @target.sms_stopped?
    assert @target.sms_verified?
  end

  test "save_sms_state with blank sms_number clears the column" do
    @target.update_columns(sms_number: "+15550001234")

    sign_in_as(ninja_admin)
    patch person_alerts_url(@target), params: {
      intent: "save_sms_state",
      person: { sms_number: "", sms_stopped: "0", sms_verified: "0" }
    }

    assert_redirected_to edit_person_alerts_path(@target)
    @target.reload
    assert_nil @target.sms_number
  end

  private

  def ensure_role(id, title)
    role = Role.find_or_initialize_by(id:)
    role.title = title
    role.new_user_eligible = false
    role.save!
  end

  def grant_role(person, role_id)
    PersonRole.find_or_create_by!(person_id: person.id, role_id:)
    RoleManager.purge_person(person.id.to_s)
  end
end
