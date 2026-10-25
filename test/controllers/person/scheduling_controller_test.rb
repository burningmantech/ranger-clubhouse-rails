# frozen_string_literal: true

require "test_helper"

class Person::SchedulingControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    Rails.cache.clear

    @target = person(:active_ranger)
    @viewer = person(:auditor_ranger)
    @past_year = Current.year - 1
    @position = positions(:training_lead)

    ensure_role(Role::ADMIN, "Admin")
    grant_role(@viewer, Role::ADMIN)
  end

  teardown do
    Rails.cache.clear
  end

  test "schedule page renders with person namespace links" do
    sign_in_as(@viewer)

    get person_scheduling_path(@target, year: Current.year)

    assert_response :success
    assert_select "#schedule-header", text: /Schedule \/ Sign-Ups/
    assert_select "a[href='#{person_path(@target)}']", text: /#{@target.callsign}/
    assert_select "a[href='#{person_scheduling_sign_ups_path(@target, year: Current.year)}']"
  end

  test "signup summary page renders shared template for person namespace" do
    sign_in_as(@viewer)

    get person_scheduling_signup_summary_path(@target, year: Current.year)

    assert_response :success
    assert_select "#hours-credits-header", text: /Hours & Credits/
    assert_select "a[href='#{person_scheduling_path(@target, year: Current.year)}']", text: /Schedule/
  end

  test "qualifications page renders for person namespace" do
    sign_in_as(@viewer)

    get person_scheduling_qualifications_path(@target, year: Current.year)

    assert_response :success
    assert_select "#qualifications-header", text: /Qualifications/
    assert_select "a[href='#{person_scheduling_path(@target, year: Current.year)}']",
                  text: /#{Current.year} Schedule & Sign-Ups/
    assert_select "#qualifications-next-step a[href=?]", person_scheduling_sign_ups_path(@target)
  end

  test "available sign-ups pages render shared person templates" do
    PersonPosition.find_or_create_by!(person: @target, position: @position)
    slot = Slot.create!(
      position: @position,
      begins: Time.zone.local(@past_year, 8, 25, 8, 0, 0),
      ends: Time.zone.local(@past_year, 8, 25, 14, 0, 0),
      max: 10,
      active: true,
      timezone: "America/Los_Angeles"
    )

    sign_in_as(@viewer)

    get person_scheduling_sign_ups_path(@target, year: @past_year)

    assert_response :success
    assert_select "a[href='#{person_scheduling_path(@target)}'].active", text: /Schedule/
    assert_select "a[href='#{person_scheduling_sign_ups_position_path(@target, position_id: @position.id, year: @past_year)}']"

    get person_scheduling_sign_ups_position_path(@target, position_id: @position.id, year: @past_year)

    assert_response :success
    assert_select "#position-shifts-header", text: /#{@position.title} Shifts/
    assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(slot)}"
  end

  test "signups action renders people signed up partial in person namespace" do
    PersonPosition.find_or_create_by!(person: @target, position: @position)
    slot = Slot.create!(
      position: @position,
      begins: 2.days.from_now,
      ends: 2.days.from_now + 6.hours,
      max: 10,
      active: true,
      timezone: "America/Los_Angeles"
    )
    PersonSlot.create!(person: @target, slot:)

    sign_in_as(@viewer)

    get person_scheduling_signups_path(@target, slot_id: slot.id)

    assert_response :success
    assert_includes @response.body, @target.callsign
  end

  # The additional-info modal renders common/scheduling/_mvr_eligible. That
  # partial used to be referenced by its bare name, which Rails resolves against
  # the controller's _prefixes — so it only ever found the copy under
  # me/available_sign_ups and raised MissingTemplate in this namespace.
  test "signing up for an MVR position renders the additional info modal" do
    # Clear the current-year signup requirements, which would otherwise bounce
    # the request before it reaches the signup.
    @target.update!(bpguid: "test-bpguid")
    PersonPhoto.create!(person: @target, status: PersonPhoto::APPROVED,
                        image_filename: "", orig_filename: "", profile_filename: "")
    # MVRDeadline has no default; retrieve_mvr_deadline can't parse a blank one.
    Setting.find_or_create_by(name: Setting::MVR_DEADLINE).update!(value: "08-01")
    Rails.cache.clear

    position = Position.create!(title: "Test MVR Position", mvr_signup_eligible: true, active: true)
    PersonPosition.find_or_create_by!(person: @target, position:)
    slot = Slot.create!(
      position:,
      begins: 2.days.from_now,
      ends: 2.days.from_now + 6.hours,
      max: 10,
      active: true,
      timezone: "America/Los_Angeles"
    )

    sign_in_as(@viewer)

    post person_scheduling_sign_ups_slot_path(@target, position_id: position.id, slot_id: slot.id),
         as: :turbo_stream

    assert_response :success
    assert_includes @response.body, "You Can Now Submit an MVR Request"
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
