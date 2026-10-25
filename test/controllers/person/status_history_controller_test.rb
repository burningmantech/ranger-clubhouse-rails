# frozen_string_literal: true

require "test_helper"

class Person::StatusHistoryControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    Rails.cache.clear

    @target = person(:active_ranger)

    @admin = person(:auditor_ranger)
    @vc = person(:echelon_ranger)
    # Holds a role in the broad PersonConcern gate but not in this page's
    # narrowed [ADMIN, VC] gate.
    @mentor = person(:ranger_with_custom_gender)
    @no_history = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    ensure_role(Role::MENTOR, "Mentor")

    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)
    grant_role(@mentor, Role::MENTOR)

    # No person_status fixtures exist; build the history under test here.
    PersonStatus.record(@target.id, "", "prospective", "imported", nil)
    PersonStatus.record(@target.id, "prospective", "active", "passed training", @vc.id)
  end

  teardown do
    Rails.cache.clear
  end

  test "admin sees the status history with source links and imported fallback" do
    sign_in_as(@admin)

    get person_status_history_path(@target)

    assert_response :success
    assert_select "body", text: /Showing 2 status logs/
    assert_select "a[href=?]", person_path(@vc), text: @vc.callsign
    assert_select "body", text: /\* imported \*/
    assert_select "body", text: /passed training/
  end

  test "vc sees the status history" do
    sign_in_as(@vc)

    get person_status_history_path(@target)

    assert_response :success
    assert_select "body", text: /Showing 2 status logs/
  end

  test "person without the admin or vc role is denied" do
    sign_in_as(@mentor)

    get person_status_history_path(@target)

    assert_redirected_to me_root_path
    assert_equal "Admin or Volunteer Coordinator role required to view status history.", flash[:error]
  end

  test "person with no status history renders the empty state" do
    sign_in_as(@vc)

    get person_status_history_path(@no_history)

    assert_response :success
    # With no card to open, the empty state carries the caveat: a gap may be the
    # whole reason nothing is listed.
    assert_select "body", text: /No status changes are recorded for this person\. The history may be inaccurate/
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
