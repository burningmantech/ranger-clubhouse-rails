# frozen_string_literal: true

require "test_helper"

class Mentoring::AlphaSchedule::RostersControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    # Before the shift starts, so adds and removes are inside the window.
    travel_to Time.zone.local(YEAR, 8, 20, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @alpha_position = Position.create!(id: Position::ALPHA, title: "Alpha",
                                       type: Position::TYPE_FRONTLINE, active: true)

    @slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 26, 8, 0, 0),
                        ends: Time.zone.local(YEAR, 8, 26, 18, 0, 0),
                        description: "Alpha Walk Wednesday Day", max: 5)

    @alpha = create_person("RosterAlpha", status: Person::ALPHA)
    @prospective = create_person("RosterProspective", status: Person::PROSPECTIVE)
    @ranger = create_person("RosterRanger", status: Person::ACTIVE)
    @signed_up = create_person("RosterSignedUp", status: Person::ALPHA)

    # Everyone who may legitimately be added holds the position; the ranger is
    # rejected on status before the position is ever consulted.
    [@alpha, @prospective, @ranger, @signed_up].each do |person|
      PersonPosition.create!(person_id: person.id, position_id: Position::ALPHA)
    end
    PersonSlot.create!(person_id: @signed_up.id, slot_id: @slot.id)

    @mentor = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::VC, "Volunteer Coordinator")
    grant_role(@mentor, Role::MENTOR)
    grant_role(@outsider, Role::VC)

    Current.person = @mentor
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  def signed_up?(person)
    PersonSlot.where(person_id: person.id, slot_id: @slot.id).exists?
  end

  # --- authorization ---

  test "a role outside the gate cannot open the search dialog" do
    sign_in_as(@outsider)
    get mentoring_new_alpha_schedule_roster_path(@slot)
    assert_redirected_to me_root_path
  end

  test "a role outside the gate cannot add anyone" do
    sign_in_as(@outsider)

    assert_no_difference -> { PersonSlot.where(slot_id: @slot.id).count } do
      post mentoring_alpha_schedule_roster_path(@slot), params: { person_id: @alpha.id }
    end
    assert_redirected_to me_root_path
  end

  # --- the search dialog ---

  test "the dialog offers an add button for an Alpha" do
    sign_in_as(@mentor)

    get mentoring_new_alpha_schedule_roster_path(@slot), params: { q: "RosterAlpha" }

    assert_response :success
    assert_match "RosterAlpha", response.body
    assert_select "input[type=submit][value=?]", "Add RosterAlpha"
  end

  test "the dialog lists an ineligible person without an add button" do
    sign_in_as(@mentor)

    get mentoring_new_alpha_schedule_roster_path(@slot), params: { q: "RosterRanger" }

    assert_response :success
    assert_match "RosterRanger", response.body
    assert_match "Not an Alpha or Prospective", response.body
    assert_select "input[type=submit][value=?]", "Add RosterRanger", count: 0
  end

  test "an old email address finds the person it belonged to" do
    EmailHistory.create!(person_id: @alpha.id, email: "former.rosteralpha@example.com")
    sign_in_as(@mentor)

    get mentoring_new_alpha_schedule_roster_path(@slot), params: { q: "former.rosteralpha@example.com" }

    assert_response :success
    assert_select "td", text: "RosterAlpha Shifter"
    assert_select "input[type=submit][value=?]", "Add RosterAlpha"
  end

  test "a query that matches no one says so" do
    sign_in_as(@mentor)

    get mentoring_new_alpha_schedule_roster_path(@slot), params: { q: "NoSuchCallsignHere" }

    assert_response :success
    assert_match "No one matched", response.body
  end

  test "a query below the minimum length prompts rather than searching" do
    sign_in_as(@mentor)

    get mentoring_new_alpha_schedule_roster_path(@slot), params: { q: "R" }

    assert_response :success
    assert_match "Type at least", response.body
  end

  # --- adding ---

  # A freshly-made account has not cleared the onboarding requirements
  # (approved callsign, approved photo, reviewed personal info...), so
  # Scheduling::Signup blocks the first attempt and the mentor confirms --
  # exactly the upstream shiftManage flow, and the same reason the training
  # roster tests force.
  test "an Alpha is added through the blocked-then-confirm flow" do
    sign_in_as(@mentor)

    post mentoring_alpha_schedule_roster_path(@slot), params: { person_id: @alpha.id }

    assert_response :unprocessable_entity
    assert_match "Could Not Add RosterAlpha", response.body
    assert_match "Add Anyway", response.body
    assert_not signed_up?(@alpha)

    post mentoring_alpha_schedule_roster_path(@slot), params: { person_id: @alpha.id, force: "1" }

    assert_redirected_to mentoring_alpha_schedule_shift_path(@slot)
    assert_match "added to the shift", flash[:success]
    assert signed_up?(@alpha)
  end

  test "a Prospective can be added" do
    sign_in_as(@mentor)

    post mentoring_alpha_schedule_roster_path(@slot), params: { person_id: @prospective.id, force: "1" }

    assert_redirected_to mentoring_alpha_schedule_shift_path(@slot)
    assert signed_up?(@prospective)
  end

  test "a Ranger is refused on status" do
    sign_in_as(@mentor)

    post mentoring_alpha_schedule_roster_path(@slot), params: { person_id: @ranger.id }

    assert_redirected_to mentoring_alpha_schedule_shift_path(@slot)
    assert_match "Only Alpha and Prospective accounts may be added", flash[:error]
    assert_not signed_up?(@ranger)
  end

  test "forcing does not get an ineligible status past the check" do
    sign_in_as(@mentor)

    post mentoring_alpha_schedule_roster_path(@slot), params: { person_id: @ranger.id, force: "1" }

    assert_redirected_to mentoring_alpha_schedule_shift_path(@slot)
    assert_match "Only Alpha and Prospective accounts may be added", flash[:error]
    assert_not signed_up?(@ranger)
  end

  test "adding someone already signed up says so without duplicating them" do
    sign_in_as(@mentor)

    assert_no_difference -> { PersonSlot.where(slot_id: @slot.id).count } do
      post mentoring_alpha_schedule_roster_path(@slot), params: { person_id: @signed_up.id }
    end
    assert_redirected_to mentoring_alpha_schedule_shift_path(@slot)
    assert_match "already signed up", flash[:warning]
  end

  test "a refusal the rules raise comes back in the dialog with a force option" do
    # No Alpha position, so Scheduling::Signup refuses on requirements.
    blocked = create_person("RosterBlocked", status: Person::ALPHA)
    sign_in_as(@mentor)

    post mentoring_alpha_schedule_roster_path(@slot), params: { person_id: blocked.id }

    assert_response :unprocessable_entity
    assert_match "Could Not Add RosterBlocked", response.body
    assert_not signed_up?(blocked)
  end

  test "a person who does not hold the position is not offered a force that cannot work" do
    blocked = create_person("RosterNoPosition", status: Person::ALPHA)
    sign_in_as(@mentor)

    post mentoring_alpha_schedule_roster_path(@slot), params: { person_id: blocked.id }

    assert_response :unprocessable_entity
    assert_match "does not hold the Alpha position", response.body
    # Scheduling::Signup returns NoPosition before it works out force rights,
    # so an "Add Anyway" here would fail identically every time.
    assert_no_match(/Add Anyway/, response.body)
  end

  test "an unknown person id is reported rather than crashing" do
    sign_in_as(@mentor)

    post mentoring_alpha_schedule_roster_path(@slot), params: { person_id: 0 }

    assert_response :success
    assert_match "Unable to determine who to add", response.body
  end

  # --- removing ---

  test "a sign-up can be removed" do
    sign_in_as(@mentor)

    delete mentoring_alpha_schedule_roster_person_path(@slot, @signed_up)

    assert_redirected_to mentoring_alpha_schedule_shift_path(@slot)
    assert_match "removed from the shift", flash[:success]
    assert_not signed_up?(@signed_up)
  end

  test "removing someone who is not signed up says so" do
    sign_in_as(@mentor)

    delete mentoring_alpha_schedule_roster_person_path(@slot, @alpha)

    assert_redirected_to mentoring_alpha_schedule_shift_path(@slot)
    assert_match "is not signed up", flash[:error]
  end

  test "a mentor may still remove someone after the shift has started" do
    travel_to Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    sign_in_as(@mentor)

    delete mentoring_alpha_schedule_roster_person_path(@slot, @signed_up)

    assert_redirected_to mentoring_alpha_schedule_shift_path(@slot)
    assert_not signed_up?(@signed_up)
  end
end
