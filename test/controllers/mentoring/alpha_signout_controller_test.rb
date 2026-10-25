# frozen_string_literal: true

require "test_helper"

# Alpha Sign-Out: the shift picker, the on-duty roster, and the bulk sign-out
# that empties it.
class Mentoring::AlphaSignoutControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  DENY_MESSAGE = "Admin or Mentor role required to open Alpha Sign-Out."
  WRITE_DENY_MESSAGE = "Shift Management role required to sign out Alphas."

  setup do
    # Event week, so entries opened this morning read as current-year.
    travel_to Time.zone.local(YEAR, 8, 25, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @alpha_position = Position.create!(id: Position::ALPHA, title: "Alpha",
                                       type: Position::TYPE_FRONTLINE, active: true)
    @mentor_position = Position.create!(id: Position::MENTOR, title: "Mentor",
                                        type: Position::TYPE_MENTORING, active: true)
    Position.create!(id: Position::MENTOR_MITTEN, title: "Mentor Mitten",
                     type: Position::TYPE_MENTORING, active: true)

    # The chosen shift begins 09:00, so the window is exactly 08:00..11:00.
    @slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 25, 9, 0, 0),
                        ends: Time.zone.local(YEAR, 8, 25, 13, 0, 0), description: "Alpha walk one")
    @inactive_slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 26, 9, 0, 0),
                                 ends: Time.zone.local(YEAR, 8, 26, 13, 0, 0),
                                 description: "Dormant walk", active: false)
    @mentor_slot = create_slot(@mentor_position, begins: Time.zone.local(YEAR, 8, 25, 9, 0, 0),
                               ends: Time.zone.local(YEAR, 8, 25, 13, 0, 0), description: "Mentor shift")

    # Fresh people rather than fixture ones: person_mentor.yml pre-seeds history
    # for several fixture people, which would bleed into the roster.
    @early_edge = create_person("SignoutEdgeEarly", status: Person::ALPHA)
    @late_edge = create_person("SignoutEdgeLate", status: Person::ALPHA)
    @too_early = create_person("SignoutTooEarly", status: Person::ALPHA)
    @too_late = create_person("SignoutTooLate", status: Person::ALPHA)
    @mid_shift = create_person("SignoutMidShift", status: Person::ALPHA)
    @already_off = create_person("SignoutAlreadyOff", status: Person::ALPHA)
    @short_shift = create_person("SignoutShortShift", status: Person::ALPHA)
    @a_mentor = create_person("SignoutMentorOnDuty")

    @admin = person(:auditor_ranger)
    @mentor = person(:echelon_ranger)
    @signer = person(:active_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
    ensure_role(Role::VC, "Volunteer Coordinator")
    grant_role(@admin, Role::ADMIN)
    grant_role(@mentor, Role::MENTOR)
    grant_role(@signer, Role::MENTOR)
    grant_role(@signer, Role::SHIFT_MANAGEMENT)
    grant_role(@outsider, Role::VC)

    Current.person = @admin
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # An open Alpha entry unless off_duty is given.
  def alpha_on_duty(person, on_duty, off_duty: nil, position_id: Position::ALPHA)
    Timesheet.create!(person: person, position_id: position_id, on_duty: on_duty,
                      off_duty: off_duty, additional_notes: "test shift")
  end

  # The four entries the window is asserted against, plus one outside it.
  def seed_window_entries
    @early_entry = alpha_on_duty(@early_edge, Time.zone.local(YEAR, 8, 25, 8, 0, 0))
    @late_entry = alpha_on_duty(@late_edge, Time.zone.local(YEAR, 8, 25, 11, 0, 0))
    @mid_entry = alpha_on_duty(@mid_shift, Time.zone.local(YEAR, 8, 25, 9, 30, 0))
    alpha_on_duty(@too_early, Time.zone.local(YEAR, 8, 25, 7, 59, 0))
    alpha_on_duty(@too_late, Time.zone.local(YEAR, 8, 25, 11, 1, 0))
  end

  # --- authorization ---

  test "an admin can open the page" do
    sign_in_as(@admin)
    get mentoring_alpha_signout_path
    assert_response :success
  end

  test "a mentor can open the page" do
    sign_in_as(@mentor)
    get mentoring_alpha_signout_path
    assert_response :success
  end

  test "a role outside the gate is turned away" do
    sign_in_as(@outsider)
    get mentoring_alpha_signout_path
    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "a mentor without shift management sees the roster read-only" do
    seed_window_entries
    sign_in_as(@mentor)

    get mentoring_alpha_signout_path(slot_id: @slot.id)

    assert_response :success
    assert_match "SignoutMidShift", response.body
    assert_match "This roster is read-only for you", response.body
    assert_no_match(/Sign Out Selected Alphas/, response.body)
    assert_no_match(/entry_ids/, response.body)
  end

  test "a mentor without shift management cannot post a sign out" do
    seed_window_entries
    sign_in_as(@mentor)

    post mentoring_alpha_signout_path, params: { slot_id: @slot.id, entry_ids: [@mid_entry.id] }

    assert_redirected_to mentoring_alpha_signout_path(slot_id: @slot.id)
    assert_equal WRITE_DENY_MESSAGE, flash[:error]
    assert_nil @mid_entry.reload.off_duty
  end

  test "shift management opens the sign out controls" do
    seed_window_entries
    sign_in_as(@signer)

    get mentoring_alpha_signout_path(slot_id: @slot.id)

    assert_response :success
    assert_match "Sign Out Selected Alphas", response.body
    assert_no_match(/This roster is read-only for you/, response.body)
  end

  # --- the picker ---

  test "the shift cards stand in for the roster until a shift is chosen" do
    sign_in_as(@signer)

    get mentoring_alpha_signout_path

    assert_response :success
    assert_match "Sign Out This Shift", response.body
    assert_match "Alpha walk one", response.body
    assert_select "#alpha-signout-on-duty", count: 0 # the roster section, not the "Every Alpha Still on Duty" button
  end

  test "an inactive shift is left out of the picker" do
    sign_in_as(@signer)

    get mentoring_alpha_signout_path

    assert_response :success
    assert_no_match(/Dormant walk/, response.body)
  end

  test "choosing a shift replaces the cards with the roster" do
    seed_window_entries
    sign_in_as(@signer)

    get mentoring_alpha_signout_path(slot_id: @slot.id)

    assert_response :success
    assert_match "Choose another shift", response.body
    assert_no_match(/Sign Out This Shift/, response.body)
  end

  test "a slot that is missing, inactive, or not an Alpha shift keeps the picker up" do
    sign_in_as(@signer)

    [0, @inactive_slot.id, @mentor_slot.id].each do |slot_id|
      get mentoring_alpha_signout_path(slot_id: slot_id)

      assert_response :success
      assert_match "Sign Out This Shift", response.body
      assert_equal "That shift is not an Alpha shift this page covers. Pick a shift from the list.",
                   flash[:error]
    end
  end

  # --- the window ---

  test "the window runs one hour before the shift to two hours after, inclusive" do
    seed_window_entries
    sign_in_as(@signer)

    get mentoring_alpha_signout_path(slot_id: @slot.id)

    assert_response :success
    assert_match "SignoutEdgeEarly", response.body
    assert_match "SignoutEdgeLate", response.body
    assert_match "SignoutMidShift", response.body
    assert_no_match(/SignoutTooEarly/, response.body)
    assert_no_match(/SignoutTooLate/, response.body)
  end

  test "only Alpha entries are listed" do
    alpha_on_duty(@a_mentor, Time.zone.local(YEAR, 8, 25, 9, 30, 0), position_id: Position::MENTOR)
    sign_in_as(@signer)

    get mentoring_alpha_signout_path(slot_id: @slot.id)

    assert_response :success
    assert_no_match(/SignoutMentorOnDuty/, response.body)
  end

  test "entries already signed out on the shift move to the disclosure" do
    seed_window_entries
    alpha_on_duty(@already_off, Time.zone.local(YEAR, 8, 25, 9, 0, 0),
                  off_duty: Time.zone.local(YEAR, 8, 25, 11, 30, 0))
    sign_in_as(@signer)

    get mentoring_alpha_signout_path(slot_id: @slot.id)

    assert_response :success
    assert_match "Already Signed Out on This Shift (1)", response.body
    assert_match "SignoutAlreadyOff", response.body
  end

  test "a very short shift is badged rather than blocked" do
    entry = alpha_on_duty(@short_shift, Current.time - 5.minutes)
    sign_in_as(@signer)

    get mentoring_alpha_signout_path(on_duty: 1)

    assert_response :success
    assert_match "Very short shift", response.body
    assert_match "sign-out-entry-#{entry.id}", response.body
  end

  # --- everywhere mode ---

  test "every-alpha mode lists open Alpha entries regardless of shift or year" do
    seed_window_entries
    stale = alpha_on_duty(@too_early, Time.zone.local(2024, 8, 25, 9, 0, 0))
    alpha_on_duty(@already_off, Time.zone.local(YEAR, 8, 25, 9, 0, 0),
                  off_duty: Time.zone.local(YEAR, 8, 25, 11, 30, 0))
    sign_in_as(@signer)

    get mentoring_alpha_signout_path(on_duty: 1)

    assert_response :success
    assert_match "Every Alpha still on duty", response.body
    assert_match "sign-out-entry-#{stale.id}", response.body
    # No bounded closed set exists in this mode, so nothing is disclosed.
    assert_no_match(/Already Signed Out on This Shift/, response.body)
    assert_no_match(/SignoutAlreadyOff/, response.body)
  end

  # --- the sign out ---

  test "checked Alphas are signed out and audit-logged" do
    seed_window_entries
    sign_in_as(@signer)

    post mentoring_alpha_signout_path,
         params: { slot_id: @slot.id, entry_ids: [@early_entry.id, @mid_entry.id] }

    assert_response :unprocessable_entity
    assert_match "Signed out 2 Alphas", response.body

    [@early_entry, @mid_entry].each do |entry|
      entry.reload
      assert_equal Current.time.to_i, entry.off_duty.to_i
      assert TimesheetLog.exists?(timesheet_id: entry.id, action: TimesheetLog::SIGNOFF)
    end

    assert_nil @late_entry.reload.off_duty
  end

  test "the just-signed-out rows stay in the on-duty panel with their result" do
    seed_window_entries
    sign_in_as(@signer)

    post mentoring_alpha_signout_path, params: { slot_id: @slot.id, entry_ids: [@mid_entry.id] }

    assert_response :unprocessable_entity
    assert_match "alpha-signout-row-#{@mid_entry.id}", response.body
    assert_match "Signed out", response.body
    # It has not fallen through to the already-signed-out disclosure.
    assert_no_match(/Already Signed Out on This Shift/, response.body)
  end

  test "an entry that is not an open Alpha shift is refused and reported" do
    seed_window_entries
    mentor_entry = alpha_on_duty(@a_mentor, Time.zone.local(YEAR, 8, 25, 9, 30, 0),
                                 position_id: Position::MENTOR)
    closed = alpha_on_duty(@already_off, Time.zone.local(YEAR, 8, 25, 9, 0, 0),
                           off_duty: Time.zone.local(YEAR, 8, 25, 11, 30, 0))
    sign_in_as(@signer)

    post mentoring_alpha_signout_path,
         params: { slot_id: @slot.id, entry_ids: [@mid_entry.id, mentor_entry.id, closed.id] }

    assert_response :unprocessable_entity
    assert_match "2 checked Alphas could not be signed out", response.body
    assert_match "Signed out 1 Alpha", response.body

    assert_not_nil @mid_entry.reload.off_duty
    assert_nil mentor_entry.reload.off_duty
    assert_equal Time.zone.local(YEAR, 8, 25, 11, 30, 0).to_i, closed.reload.off_duty.to_i
  end

  test "submitting nothing checked redirects back to the same shift" do
    seed_window_entries
    sign_in_as(@signer)

    post mentoring_alpha_signout_path, params: { slot_id: @slot.id, entry_ids: [""] }

    assert_redirected_to mentoring_alpha_signout_path(slot_id: @slot.id)
    assert_equal "Check at least one Alpha to sign out.", flash[:alert]
  end

  # to_i read "abc" as entry 0, reported as an Alpha who could not be signed
  # out, and "#{id}x" as that entry, which it signed out.
  test "entry ids that are not ids are neither signed out nor reported" do
    seed_window_entries
    sign_in_as(@signer)

    post mentoring_alpha_signout_path,
         params: { slot_id: @slot.id, entry_ids: [@mid_entry.id, "abc", "#{@early_entry.id}x"] }

    assert_response :unprocessable_entity
    assert_match "Signed out 1 Alpha", response.body
    assert_no_match(/could not be signed out/, response.body)
    assert_nil @early_entry.reload.off_duty
  end

  test "signing out closes the Alpha's place in their pod" do
    seed_window_entries
    set = Pod.create_alpha_set!(@slot)
    alpha_pod = set.sub_pods.find(&:alpha?)
    membership = PersonPod.create!(pod: alpha_pod, person: @mid_shift,
                                   timesheet_id: @mid_entry.id, sort_index: 1)
    alpha_pod.refresh_person_count!
    sign_in_as(@signer)

    post mentoring_alpha_signout_path, params: { slot_id: @slot.id, entry_ids: [@mid_entry.id] }

    assert_response :unprocessable_entity
    assert_equal Current.time.to_i, membership.reload.left_at.to_i
    # left_at records that the shift ended, not that the person left: the count
    # is deliberately unchanged so a pod does not disband itself when everyone
    # signs out. See Pod.shift_ended.
    assert_nil membership.removed_at
    assert_equal 1, alpha_pod.reload.person_count
  end

  test "every-alpha mode holds the just-signed-out rows on the page" do
    seed_window_entries
    sign_in_as(@signer)

    post mentoring_alpha_signout_path, params: { on_duty: 1, entry_ids: [@mid_entry.id] }

    assert_response :unprocessable_entity
    assert_match "alpha-signout-row-#{@mid_entry.id}", response.body
    assert_match "Every Alpha still on duty", response.body
  end
end
