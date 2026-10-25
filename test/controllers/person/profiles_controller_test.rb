# frozen_string_literal: true

require "test_helper"

class Person::ProfilesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    Rails.cache.clear

    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @vc = person(:echelon_ranger)
    @em = person(:ranger_with_custom_gender)
    @view_pii_user = person(:retired_ranger)
    @no_one = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::VIEW_PII, "View PII")

    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)
    grant_role(@em, Role::EVENT_MANAGEMENT)
    grant_role(@view_pii_user, Role::VIEW_PII)

    @target.update!(
      street1: "100 Test Lane",
      city: "Black Rock City",
      state: "Nevada",
      zip: "89412",
      country: "United States",
      home_phone: "+17755550102",
      email: "target@example.com",
      camp_location: "Camp Test, 6:00 & B",
      emergency_contact: "Jane Doe, sister, 555-9999",
      tshirt_swag_id: nil,
      long_sleeve_swag_id: nil
    )
  end

  teardown do
    Rails.cache.clear
  end

  # ----- Access gating -----

  test "admin can view another person's profile" do
    sign_in_as(@admin)
    get person_profile_path(@target)
    assert_response :success
    assert_match @target.callsign, response.body
  end

  test "vc can view another person's profile" do
    sign_in_as(@vc)
    get person_profile_path(@target)
    assert_response :success
  end

  test "event_management can view another person's profile" do
    sign_in_as(@em)
    get person_profile_path(@target)
    assert_response :success
  end

  test "view_pii alone can view another person's profile" do
    sign_in_as(@view_pii_user)
    get person_profile_path(@target)
    assert_response :success
  end

  test "user with no qualifying role is redirected" do
    sign_in_as(@no_one)
    get person_profile_path(@target)
    assert_redirected_to me_root_path
  end

  # ----- Section visibility -----

  test "admin sees mailing address" do
    sign_in_as(@admin)
    get person_profile_path(@target)
    assert_match "100 Test Lane", response.body
  end

  test "vc sees mailing address" do
    sign_in_as(@vc)
    get person_profile_path(@target)
    assert_match "100 Test Lane", response.body
  end

  test "view_pii sees mailing address" do
    sign_in_as(@view_pii_user)
    get person_profile_path(@target)
    assert_match "100 Test Lane", response.body
  end

  test "event_management does NOT see mailing address" do
    sign_in_as(@em)
    get person_profile_path(@target)
    assert_no_match "100 Test Lane", response.body
  end

  test "admin sees email and phone in identity card" do
    sign_in_as(@admin)
    get person_profile_path(@target)
    assert_match "target@example.com", response.body
  end

  test "event_management does NOT see email/phone in identity card" do
    sign_in_as(@em)
    get person_profile_path(@target)
    assert_no_match "target@example.com", response.body
  end

  test "view_pii does NOT see identity basics card" do
    sign_in_as(@view_pii_user)
    get person_profile_path(@target)
    assert_no_match "Legal name", response.body
  end

  test "admin sees emergency contact" do
    sign_in_as(@admin)
    get person_profile_path(@target)
    assert_match "Jane Doe", response.body
  end

  test "event_management sees emergency contact (event_management grants can_view_emergency_contact) while Event Management On Playa enabled" do
    Setting.find_or_create_by(name: Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED).update!(value: "true")
    sign_in_as(@em)
    get person_profile_path(@target)
    assert_match "Jane Doe", response.body
  end

  test "event_management cannot see emergency contact (event_management grants can_view_emergency_contact) while Event Management On Playa disabled" do
    Setting.find_or_create_by(name: Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED).update!(value: "false")
    sign_in_as(@em)
    get person_profile_path(@target)
    assert_no_match "Jane Doe", response.body
  end

  test "view_pii sees emergency contact denial message" do
    sign_in_as(@view_pii_user)
    get person_profile_path(@target)
    assert_match "not permitted to view the emergency contact", response.body
  end

  test "admin sees Alert Preferences section" do
    sign_in_as(@admin)
    get person_profile_path(@target)
    assert_match "Alert Preferences", response.body
  end

  test "vc does NOT see Alert Preferences section" do
    sign_in_as(@vc)
    get person_profile_path(@target)
    assert_no_match "Alert Preferences", response.body
  end

  test "event_management does NOT see Alert Preferences section" do
    sign_in_as(@em)
    get person_profile_path(@target)
    assert_no_match "Alert Preferences", response.body
  end

  test "non-admin does NOT see My Information Is Correct button" do
    sign_in_as(@vc)
    get person_profile_path(@target)
    assert_no_match "My Information Is Correct", response.body
  end

  # ----- Edit gating -----

  test "admin can GET edit for any section" do
    sign_in_as(@admin)
    get person_edit_profile_section_path(@target, "identity-info")
    assert_response :success
  end

  test "vc can GET edit for any section" do
    sign_in_as(@vc)
    get person_edit_profile_section_path(@target, "mailing-address")
    assert_response :success
  end

  test "event_management cannot GET edit (read-only)" do
    sign_in_as(@em)
    get person_edit_profile_section_path(@target, "identity-info")
    assert_redirected_to person_profile_path(@target)
  end

  test "view_pii cannot GET edit (read-only)" do
    sign_in_as(@view_pii_user)
    get person_edit_profile_section_path(@target, "mailing-address")
    assert_redirected_to person_profile_path(@target)
  end

  test "admin can update a section" do
    sign_in_as(@admin)
    patch person_profile_section_path(@target, "camp"),
          params: { person: { camp_location: "Updated by admin" } }
    assert_redirected_to person_profile_path(@target)
    @target.reload
    assert_equal "Updated by admin", @target.camp_location
  end

  test "vc can update a section" do
    sign_in_as(@vc)
    patch person_profile_section_path(@target, "emergency-contact"),
          params: { person: { emergency_contact: "Updated EC by VC" } }
    assert_redirected_to person_profile_path(@target)
    @target.reload
    assert_equal "Updated EC by VC", @target.emergency_contact
  end

  test "event_management cannot update a section" do
    sign_in_as(@em)
    original = @target.camp_location
    patch person_profile_section_path(@target, "camp"),
          params: { person: { camp_location: "Should not save" } }
    assert_redirected_to person_profile_path(@target)
    @target.reload
    assert_equal original, @target.camp_location
  end

  test "admin update writes ActionLog entry" do
    sign_in_as(@admin)
    assert_difference -> { ActionLog.where(event: "person-profile-update").count }, 1 do
      patch person_profile_section_path(@target, "camp"),
            params: { person: { camp_location: "ActionLog test camp" } }
    end
    log = ActionLog.where(event: "person-profile-update").order(:id).last
    assert_equal @admin.id, log.person_id
    assert_match @target.callsign, log.message
  end

  # ----- mark_reviewed not available on admin route -----

  test "mark_reviewed route is not exposed on admin profile" do
    assert_raises NoMethodError do
      mark_reviewed_person_profile_path(@target)
    end
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
