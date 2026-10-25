# frozen_string_literal: true

require "test_helper"

class PersonStatusManagementTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 8, 12, 0, 0)

    Rails.cache.clear
    Current.reset

    @actor = person(:auditor_ranger)
    Current.person = @actor

    HandleReservation.delete_all

    ensure_position(Position::ALPHA, "Alpha")
    ensure_position(Position::DIRT_SHINY_PENNY, "Shiny Penny")

    @all_rangers_position = create_position("All Ranger", all_rangers: true)
    @new_user_position = create_position("New User Pos", new_user_eligible: true)
    @special_position = create_position("Special Pos")

    @new_user_role = create_role("New User Role", new_user_eligible: true)
    @special_role = create_role("Special Role")
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  test "alpha to active grants defaults, shiny penny, and removes alpha position" do
    person = person(:alpha_ranger)
    PersonPosition.create!(person_id: person.id, position_id: Position::ALPHA)

    person.status = Person::ACTIVE

    assert_difference("PersonStatus.count", 1) do
      PersonStatusManagement.change(person: person, old_status: Person::ALPHA, reason: "activated")
    end

    assert PersonPosition.have_position?(person.id, @all_rangers_position.id)
    assert PersonPosition.have_position?(person.id, Position::DIRT_SHINY_PENNY)
    assert_not PersonPosition.have_position?(person.id, Position::ALPHA)
    assert_includes PersonRole.find_role_ids_for_person(person.id), @new_user_role.id
  end

  test "active to bonked removes positions and future signups" do
    person = person(:ranger_with_custom_gender)
    PersonPosition.create!(person_id: person.id, position_id: @special_position.id)
    slot = create_future_signup(person, @special_position)

    person.status = Person::BONKED
    PersonStatusManagement.change(person: person, old_status: Person::ACTIVE, reason: "discipline")

    assert_not PersonPosition.have_position?(person.id, @special_position.id)
    assert_not PersonSlot.have_slot?(person.id, slot.id)
  end

  test "active to retired removes teams and keeps new user defaults" do
    person = person(:ranger_with_custom_gender)
    PersonTeam.create!(person_id: person.id, team_id: teams(:green_dot_cadre).id)
    PersonPosition.create!(person_id: person.id, position_id: @special_position.id)
    PersonRole.create!(person_id: person.id, role_id: @special_role.id)
    slot = create_future_signup(person, @special_position)

    person.status = Person::RETIRED
    PersonStatusManagement.change(person: person, old_status: Person::ACTIVE, reason: "retired")

    assert_empty PersonTeam.where(person_id: person.id)
    assert PersonPosition.have_position?(person.id, @new_user_position.id)
    assert_not PersonPosition.have_position?(person.id, @special_position.id)
    assert_includes PersonRole.find_role_ids_for_person(person.id), @new_user_role.id
    assert_not_includes PersonRole.find_role_ids_for_person(person.id), @special_role.id
    assert_not PersonSlot.have_slot?(person.id, slot.id)
  end

  test "prospective to past prospective removes roles, positions, teams, and future signups" do
    person = person(:prospective_ranger)
    PersonTeam.create!(person_id: person.id, team_id: teams(:mentor_cadre).id)
    PersonPosition.create!(person_id: person.id, position_id: @special_position.id)
    PersonRole.create!(person_id: person.id, role_id: @special_role.id)
    slot = create_future_signup(person, @special_position)

    person.status = Person::PAST_PROSPECTIVE
    PersonStatusManagement.change(person: person, old_status: Person::PROSPECTIVE, reason: "screened out")

    assert_empty PersonTeam.where(person_id: person.id)
    assert_empty PersonPosition.where(person_id: person.id)
    assert_empty PersonRole.where(person_id: person.id)
    assert_not PersonSlot.have_slot?(person.id, slot.id)
  end

  test "active to suspended clears asset authorization without removing memberships" do
    person = person(:ranger_with_custom_gender)
    PersonTeam.create!(person_id: person.id, team_id: teams(:mentor_cadre).id)
    PersonPosition.create!(person_id: person.id, position_id: @special_position.id)
    PersonRole.create!(person_id: person.id, role_id: @special_role.id)
    event = PersonEvent.create!(person_id: person.id, year: Current.year, asset_authorized: true)

    person.status = Person::SUSPENDED
    PersonStatusManagement.change(person: person, old_status: Person::ACTIVE, reason: "suspended")

    assert PersonTeam.exists?(person_id: person.id, team_id: teams(:mentor_cadre).id)
    assert PersonPosition.have_position?(person.id, @special_position.id)
    assert_includes PersonRole.find_role_ids_for_person(person.id), @special_role.id
    assert_not event.reload.asset_authorized
  end

  test "active to deceased reserves approved non-vintage handle and removes destructive state" do
    person = person(:ranger_with_custom_gender)
    PersonTeam.create!(person_id: person.id, team_id: teams(:khaki_team).id)
    PersonPosition.create!(person_id: person.id, position_id: @special_position.id)
    PersonRole.create!(person_id: person.id, role_id: @special_role.id)
    slot = create_future_signup(person, @special_position)

    person.status = Person::DECEASED
    PersonStatusManagement.change(person: person, old_status: Person::ACTIVE, reason: "deceased")

    assert_empty PersonTeam.where(person_id: person.id)
    assert_empty PersonPosition.where(person_id: person.id)
    assert_empty PersonRole.where(person_id: person.id)
    assert_not PersonSlot.have_slot?(person.id, slot.id)
    assert HandleReservation.exists?(
      normalized_handle: WordUtils.normalize_word(person.callsign),
      reservation_type: HandleReservation::RESERVATION_TYPE_DECEASED_PERSON
    )
    reservation = HandleReservation.find_by!(
      normalized_handle: WordUtils.normalize_word(person.callsign),
      reservation_type: HandleReservation::RESERVATION_TYPE_DECEASED_PERSON
    )
    assert_equal person.callsign, reservation.handle
    assert_equal WordUtils.normalize_word(person.callsign), reservation.normalized_handle
  end

  test "person update triggers status management through the model callback" do
    person = person(:ranger_with_custom_gender)
    PersonPosition.create!(person_id: person.id, position_id: @special_position.id)
    slot = create_future_signup(person, @special_position)

    person.audit_reason = "callback transition"

    assert_difference("PersonStatus.count", 1) do
      person.update!(status: Person::BONKED)
    end

    status = PersonStatus.where(person_id: person.id).order(:created_at).last

    assert_equal Person::ACTIVE, status.old_status
    assert_equal Person::BONKED, status.new_status
    assert_equal "callback transition", status.reason
    assert_not PersonSlot.have_slot?(person.id, slot.id)
    assert_not PersonPosition.have_position?(person.id, @special_position.id)
  end

  test "same status save is a no-op" do
    person = person(:ranger_with_custom_gender)
    original_updated_at = person.updated_at

    assert_no_difference("PersonStatus.count") do
      person.update!(status: Person::ACTIVE)
    end

    assert_equal original_updated_at, person.reload.updated_at
  end

  private

  def create_position(title, **attributes)
    Position.create!(
      {
        title: title,
        active: true,
        awards_eligible: false,
        awards_auto_grant: false,
        awards_grants_service_year: false,
        count_hours: true
      }.merge(attributes)
    )
  end

  def ensure_position(id, title)
    position = Position.find_or_initialize_by(id: id)
    position.assign_attributes(
      title: title,
      active: true,
      awards_eligible: false,
      awards_auto_grant: false,
      awards_grants_service_year: false,
      count_hours: true
    )
    position.save!
    position
  end

  def create_role(title, **attributes)
    Role.create!({ title: title, new_user_eligible: false }.merge(attributes))
  end

  def create_future_signup(person, position)
    slot = Slot.create!(
      position: position,
      begins: 2.days.from_now,
      ends: 2.days.from_now + 2.hours,
      active: true,
      description: "Future shift",
      max: 5
    )

    PersonSlot.create!(person_id: person.id, slot_id: slot.id)
    slot
  end
end
