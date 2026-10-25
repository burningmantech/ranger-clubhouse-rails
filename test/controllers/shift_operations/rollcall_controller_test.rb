# frozen_string_literal: true

require "test_helper"

class ShiftOperations::RollcallControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2031

  setup do
    Rails.cache.clear
    Current.reset

    @now = Time.zone.local(YEAR, 8, 30, 20, 0, 0)
    travel_to @now

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")

    @admin = person(:active_ranger)
    @ranger = person(:echelon_ranger)
    grant_role(@admin, Role::ADMIN)

    # Built rather than taken from the fixtures: a rollcall check-in has to be
    # blocker-free to reach the happy path, and every position fixture leaves
    # no_training_required false.
    @position = create_rollcall_position("Burn Perimeter Test")
    @other_position = create_rollcall_position("Sandman Test")
    PersonPosition.find_or_create_by!(person_id: @ranger.id, position_id: @position.id)
    PersonPosition.find_or_create_by!(person_id: @ranger.id, position_id: @other_position.id)

    # Inside the rollcall window: begins within two hours of now.
    @slot = Slot.create!(position_id: @position.id, description: "Burn Night",
                         begins: @now + 30.minutes, ends: @now + 6.hours,
                         max: 20, active: true)
    PersonSlot.create!(person_id: @ranger.id, slot_id: @slot.id)

    sign_in_as(@admin)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  def create_rollcall_position(title, **overrides)
    Position.create!({ title: title, type: Position::TYPE_FRONTLINE, active: true,
                       no_training_required: true }.merge(overrides))
  end

  # mode is spelled the way a rendered row spells it -- the symbol's own to_s,
  # not the hyphenated route path. A test that invents its own dialect is
  # testing a contract the browser never uses; that is how the sign-out mode
  # bug survived a green suite.
  def roster_params(**overrides)
    { person_id: @ranger.id, mode: "sign_in", position_id: @position.id,
      slot_id: @slot.id }.merge(overrides)
  end

  def row_id = "rollcall-person-#{@ranger.id}"

  def open_entry = Timesheet.find_person_on_duty(@ranger.id)

  def create_timesheet(person, position, on_duty:, off_duty: nil)
    Timesheet.create!(person:, position:, on_duty:, off_duty:, additional_notes: "test shift")
  end

  def sign_the_ranger_in! = create_timesheet(@ranger, @position, on_duty: @now - 1.hour)

  # ---------------------------------------------------------------- access

  test "admin may open every page" do
    get shift_operations_rollcall_path
    assert_response :success

    get shift_operations_rollcall_sign_in_path
    assert_response :success

    get shift_operations_rollcall_sign_out_path
    assert_response :success
  end

  test "shift management may open the page" do
    grant_role(@ranger, Role::SHIFT_MANAGEMENT)
    sign_in_as(@ranger)

    get shift_operations_rollcall_path

    assert_response :success
  end

  test "a Ranger with neither role is turned away" do
    sign_in_as(@ranger)

    get shift_operations_rollcall_path

    assert_redirected_to me_root_path
  end

  test "a Ranger with neither role cannot sign anyone in" do
    sign_in_as(@ranger)

    assert_no_difference "Timesheet.count" do
      post shift_operations_rollcall_check_in_path, params: roster_params
    end
    assert_redirected_to me_root_path
  end

  # ---------------------------------------------------------------- rosters

  test "the shift window offers only slots starting within it" do
    outside = Slot.create!(position_id: @position.id, description: "Tomorrow",
                           begins: @now + 8.hours, ends: @now + 12.hours,
                           max: 20, active: true)

    get shift_operations_rollcall_sign_in_path(position_id: @position.id)

    assert_select "select#slot_id option[value=?]", @slot.id.to_s
    assert_select "select#slot_id option[value=?]", outside.id.to_s, count: 0
  end

  test "a position offering exactly one shift selects it without being asked" do
    get shift_operations_rollcall_sign_in_path(position_id: @position.id)

    assert_response :success
    assert_select "##{row_id}"
  end

  test "the sign-in roster lists the sign-ups and the sign-out roster lists who is out" do
    get shift_operations_rollcall_sign_in_path(position_id: @position.id)
    assert_select "##{row_id}"
    assert_select "##{row_id} button[aria-label=?]", "Sign in #{@ranger.callsign}"

    sign_the_ranger_in!
    get shift_operations_rollcall_sign_out_path(position_id: @position.id)
    assert_select "##{row_id}"
  end

  test "row DOM ids are unique across a roster" do
    other = person(:auditor_ranger)
    PersonSlot.create!(person_id: other.id, slot_id: @slot.id)

    get shift_operations_rollcall_sign_in_path(position_id: @position.id)

    assert_unique_dom_ids
  end

  # assert_unique_dom_ids only ever sees a full page render, and a stream is not
  # one -- so a stream that duplicates an id on arrival slips past it. The count
  # partial carries the target's own id, which makes `update` (inner HTML) the
  # wrong action: it would nest the element inside itself and leave two
  # #rollcall-count on the page for the layout's morph to reconcile.
  test "the count stream replaces its target rather than nesting inside it" do
    post shift_operations_rollcall_check_in_path, params: roster_params

    stream = css_select("turbo-stream[target=rollcall-count]").first
    assert_equal "replace", stream["action"]
    assert_equal 1, stream.css("[id=rollcall-count]").size,
                 "the streamed markup must carry the id exactly once"
  end

  # Every state, because the label is the only thing a reader who cannot see
  # the row has. A previous version derived it from the badge, which made every
  # Sign Out row announce "currently tap to sign out" -- and the suite missed it
  # because it only ever asserted the states the Sign In roster shows.
  test "each row state announces its own action" do
    get shift_operations_rollcall_sign_in_path(position_id: @position.id)
    assert_select "##{row_id} button[aria-label=?]", "Sign in #{@ranger.callsign}"

    create_timesheet(@ranger, @other_position, on_duty: @now - 1.hour)
    get shift_operations_rollcall_sign_in_path(position_id: @position.id)
    assert_select "##{row_id} button[aria-label=?]",
                  "Sign out #{@ranger.callsign}, who is on duty on another position"

    get shift_operations_rollcall_sign_out_path(position_id: @other_position.id)
    assert_select "##{row_id} button[aria-label=?]", "Sign out #{@ranger.callsign}"

    post shift_operations_rollcall_check_out_path,
         params: roster_params(mode: "sign_out", position_id: @other_position.id, slot_id: nil)
    assert_select "turbo-stream[target=?] template", row_id do
      assert_select "button[aria-label=?]", "Resume #{@ranger.callsign}'s shift"
    end
  end

  # ------------------------------------------------------------ turbo streams

  test "signing a Ranger in answers with a stream replacing the row and the count" do
    assert_difference "Timesheet.count", 1 do
      post shift_operations_rollcall_check_in_path, params: roster_params
    end

    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_select "turbo-stream[action=replace][target=?]", row_id
    assert_select "turbo-stream[action=replace][target=rollcall-count]"
    assert open_entry, "the Ranger should now be on duty"
  end

  test "the replaced row comes back showing the Ranger on duty" do
    post shift_operations_rollcall_check_in_path, params: roster_params

    assert_select "turbo-stream[target=?] template", row_id do
      assert_select "button[aria-label=?]", "Sign out #{@ranger.callsign}, who is on duty"
    end
  end

  test "a blocked check-in writes nothing and streams the blocked dialog" do
    blocked = Position.create!(title: "Blocked Rollcall Position", type: Position::TYPE_FRONTLINE,
                               no_training_required: false, active: true)
    PersonPosition.find_or_create_by!(person_id: @ranger.id, position_id: blocked.id)
    slot = Slot.create!(position_id: blocked.id, description: "Blocked Shift",
                        begins: @now + 30.minutes, ends: @now + 6.hours, max: 20, active: true)
    PersonSlot.create!(person_id: @ranger.id, slot_id: slot.id)

    assert_no_difference "Timesheet.count" do
      post shift_operations_rollcall_check_in_path,
           params: roster_params(position_id: blocked.id, slot_id: slot.id)
    end

    assert_equal Mime[:turbo_stream], response.media_type
    assert_select "turbo-stream[action=update][target=modal]"
    assert_select "turbo-stream[target=modal] template", /Check In Is Blocked/
    # No force affordance on this page, for anyone.
    assert_select "turbo-stream[target=modal] template textarea[name=?]",
                  "signin_force_reason", count: 0
  end

  test "an admin who could force elsewhere is still not offered the option here" do
    ensure_role(Role::CAN_FORCE_SHIFT, "Force Shift Start")
    grant_role(@admin, Role::CAN_FORCE_SHIFT)
    blocked = Position.create!(title: "Blocked Rollcall Position 2",
                               type: Position::TYPE_FRONTLINE,
                               no_training_required: false, active: true)
    PersonPosition.find_or_create_by!(person_id: @ranger.id, position_id: blocked.id)

    assert_no_difference "Timesheet.count" do
      post shift_operations_rollcall_check_in_path, params: roster_params(position_id: blocked.id)
    end

    assert_select "turbo-stream[target=modal] template", /HQ window/
    assert_select "turbo-stream[target=modal] template input[name=force_sign_in]", count: 0
  end

  test "signing in a Ranger who is already on duty reports it and redraws the row" do
    sign_the_ranger_in!

    assert_no_difference "Timesheet.count" do
      post shift_operations_rollcall_check_in_path, params: roster_params
    end

    assert_equal Mime[:turbo_stream], response.media_type
    assert_select "turbo-stream[action=replace][target=?]", row_id
  end

  test "a position the Ranger does not hold is refused without writing" do
    unheld = Position.create!(title: "Unheld Rollcall Position", type: Position::TYPE_FRONTLINE,
                              no_training_required: true, active: true)

    assert_no_difference "Timesheet.count" do
      post shift_operations_rollcall_check_in_path, params: roster_params(position_id: unheld.id)
    end

    assert_select "turbo-stream[action=replace][target=?]", row_id
  end

  # The regression this file previously missed: every sign-out test below spelled
  # the mode by hand, and picked the spelling the routes use rather than the one
  # the rows actually serialise. The controller read only the hand-written form,
  # so a real sign-out tap came back rendered as a sign-in row with a stale
  # count, and the suite stayed green. Read the value out of the page instead.
  test "the mode a rendered sign-out row posts is understood as a sign-out" do
    sign_the_ranger_in!

    get shift_operations_rollcall_sign_out_path(position_id: @position.id)
    posted_mode = css_select("##{row_id} input[name=mode]").first["value"]

    post shift_operations_rollcall_check_out_path,
         params: roster_params(mode: posted_mode, slot_id: nil)

    assert_select "turbo-stream[target=?] template", row_id do
      assert_select "button[aria-label=?]", "Resume #{@ranger.callsign}'s shift"
    end
    assert_select "turbo-stream[action=replace][target=rollcall-count]"
  end

  test "signing a Ranger out closes the entry and streams the row" do
    entry = sign_the_ranger_in!

    post shift_operations_rollcall_check_out_path, params: roster_params(mode: "sign_out")

    assert_equal Mime[:turbo_stream], response.media_type
    assert_select "turbo-stream[action=replace][target=?]", row_id
    assert entry.reload.off_duty, "the entry should be closed"
    assert_nil open_entry
  end

  test "the signed-off row offers to resume the shift it just ended" do
    entry = sign_the_ranger_in!

    post shift_operations_rollcall_check_out_path, params: roster_params(mode: "sign_out")

    assert_select "turbo-stream[target=?] template", row_id do
      assert_select "button[aria-label=?]", "Resume #{@ranger.callsign}'s shift"
      assert_select "input[name=entry_id][value=?]", entry.id.to_s
    end
  end

  test "resuming reopens the same entry rather than creating a new one" do
    entry = sign_the_ranger_in!
    entry.update!(off_duty: @now - 5.minutes)

    assert_no_difference "Timesheet.count" do
      post shift_operations_rollcall_resume_path,
           params: roster_params(mode: "sign_out", entry_id: entry.id)
    end

    assert_nil entry.reload.off_duty
    assert_select "turbo-stream[action=replace][target=?]", row_id
  end

  # Somebody else got there first. The row has nothing to sign off and nothing
  # to resume, so it must not wear the green "Signed off" success state with a
  # resume button whose entry_id is nil -- that row can only ever be refused.
  test "a sign-out row for someone no longer on duty is inert, not a green success" do
    post shift_operations_rollcall_check_out_path,
         params: roster_params(mode: "sign_out", slot_id: nil)

    assert_select "turbo-stream[target=?] template", row_id do
      assert_select "[role=status][aria-label=?]", "#{@ranger.callsign} is no longer on duty"
      assert_select "form", count: 0, message: "an inert row must offer no tap"
      assert_select "*", text: /Signed off/, count: 0
    end
  end

  # The row asserted which entry was open. Ending "whatever is open" instead
  # would close a shift the operator never saw on this roster.
  test "check-out refuses when the open entry is not the one the row asserted" do
    entry = sign_the_ranger_in!

    post shift_operations_rollcall_check_out_path,
         params: roster_params(mode: "sign_out", slot_id: nil, entry_id: entry.id + 1000)

    assert_nil entry.reload.off_duty, "the open shift must not be closed"
    assert_select "turbo-stream", /changed since this roster was drawn/
  end

  test "check-out proceeds when the asserted entry is the open one" do
    entry = sign_the_ranger_in!

    post shift_operations_rollcall_check_out_path,
         params: roster_params(mode: "sign_out", slot_id: nil, entry_id: entry.id)

    assert entry.reload.off_duty, "the asserted entry should be closed"
  end

  test "resume refuses an entry belonging to somebody else" do
    other = person(:auditor_ranger)
    entry = create_timesheet(other, @position, on_duty: @now - 2.hours, off_duty: @now - 1.hour)

    post shift_operations_rollcall_resume_path,
         params: roster_params(mode: "sign_out", entry_id: entry.id)

    assert entry.reload.off_duty, "another Ranger's entry must not be reopened"
    assert_select "turbo-stream", /no longer available to resume/
  end

  # Resume is the undo for the tap just made, nothing more. Unbounded, a
  # hand-posted entry_id reopens a shift closed years ago and records an open
  # entry tens of thousands of hours long that only Mass Sign-Out can see.
  test "resume refuses a shift that ended long ago" do
    stale = create_timesheet(@ranger, @position, on_duty: @now - 10.hours,
                                                 off_duty: @now - 9.hours)

    post shift_operations_rollcall_resume_path,
         params: roster_params(mode: "sign_out", slot_id: nil, entry_id: stale.id)

    assert stale.reload.off_duty, "a long-closed shift must not be reopened"
    assert_select "turbo-stream", /no longer available to resume/
  end

  test "resume accepts the shift this page just ended" do
    entry = sign_the_ranger_in!
    post shift_operations_rollcall_check_out_path,
         params: roster_params(mode: "sign_out", slot_id: nil, entry_id: entry.id)

    post shift_operations_rollcall_resume_path,
         params: roster_params(mode: "sign_out", slot_id: nil, entry_id: entry.id)

    assert_nil entry.reload.off_duty, "the shift just ended here should reopen"
  end

  # --------------------------------------------------------------- set time

  test "a set check-in time backdates the entry" do
    post shift_operations_rollcall_check_in_path, params: roster_params(start_time: "18:15")

    assert_equal Time.zone.local(YEAR, 8, 30, 18, 15, 0), open_entry.on_duty
  end

  # 23:45 read at 20:00 can only mean last night, which is beyond the lookback.
  test "a check-in time outside the lookback is refused without writing" do
    assert_no_difference "Timesheet.count" do
      post shift_operations_rollcall_check_in_path, params: roster_params(start_time: "23:45")
    end

    assert_select "turbo-stream", /within the last several hours/
  end

  # Rollcall runs through the burn, so past midnight the roster still carries
  # last night's shifts and a time later than now is last night's, not the
  # future. Refusing it would leave the operator no truthful time to enter.
  test "past midnight a check-in time later than now records last night" do
    travel_to Time.zone.local(YEAR, 8, 31, 0, 30, 0)

    post shift_operations_rollcall_check_in_path, params: roster_params(start_time: "23:45")

    assert_equal Time.zone.local(YEAR, 8, 30, 23, 45, 0), open_entry.on_duty
  end

  test "a check-in time inside a finished shift is refused without writing" do
    create_timesheet(@ranger, @position, on_duty: @now - 4.hours, off_duty: @now - 2.hours)

    assert_no_difference "Timesheet.count" do
      post shift_operations_rollcall_check_in_path, params: roster_params(start_time: "17:00")
    end

    assert_select "turbo-stream", /already finished/
  end

  test "the set time dialog opens from the query string and survives a reload" do
    get shift_operations_rollcall_sign_in_path(position_id: @position.id, slot_id: @slot.id,
                                               set_time: 1)

    assert_select "#rollcall-set-time-modal"
    assert_select "input[type=time][name=start_time]"
  end

  # The set time has to survive a row that passes through a sign-out, or the
  # banner keeps promising a time the next tap no longer applies.
  test "a set time survives a sign-out and is still on the row that comes back" do
    sign_the_ranger_in!

    post shift_operations_rollcall_check_out_path, params: roster_params(start_time: "18:15")

    assert_select "turbo-stream[target=?] template", row_id do
      assert_select "input[name=start_time][value=?]", "18:15"
    end
  end

  test "a set time is carried into every row's sign-in form" do
    get shift_operations_rollcall_sign_in_path(position_id: @position.id, slot_id: @slot.id,
                                               start_time: "18:15")

    assert_select "##{row_id} input[name=start_time][value=?]", "18:15"
  end

  # ------------------------------------------------------------------ counts

  test "the count reports how many of the roster are signed in" do
    get shift_operations_rollcall_sign_in_path(position_id: @position.id)
    assert_select "#rollcall-count", /0 of 1 signed in/

    sign_the_ranger_in!
    get shift_operations_rollcall_sign_in_path(position_id: @position.id)
    assert_select "#rollcall-count", /1 of 1 signed in/
  end

  test "the sign-out count still renders once the last Ranger goes off duty" do
    sign_the_ranger_in!

    get shift_operations_rollcall_sign_out_path(position_id: @position.id)
    assert_select "#rollcall-count", /1 Ranger still on duty/

    post shift_operations_rollcall_check_out_path,
         params: roster_params(mode: "sign_out", slot_id: nil)

    # The position drops out of the on-duty grouping entirely at this point, so
    # a count derived from it has to answer zero rather than nothing -- a
    # dropped stream leaves the old number frozen on screen.
    assert_select "turbo-stream[action=replace][target=rollcall-count] template",
                  /0 Rangers still on duty/
  end

  test "a Ranger out on another position counts as not signed in and reads as elsewhere" do
    create_timesheet(@ranger, @other_position, on_duty: @now - 1.hour)

    get shift_operations_rollcall_sign_in_path(position_id: @position.id)

    assert_select "#rollcall-count", /0 of 1 signed in/
    assert_select "##{row_id}", /On duty elsewhere/
  end
end
