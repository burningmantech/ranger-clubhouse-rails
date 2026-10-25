# frozen_string_literal: true

require "test_helper"

class ShiftManageTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper
  include TimesheetAdminTestHelper

  setup do
    travel_to Time.zone.local(2026, 8, 30, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @person = person(:active_ranger)
    @operator = person(:auditor_ranger)
    Current.person = @operator

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::CAN_FORCE_SHIFT, "Force Shift Start")
    ensure_role(Role::SHIFT_MANAGEMENT_SELF, "Shift Management Self")

    @position = create_position!("Sunrise Patrol")
    grant_position(@position)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  # --- sign_in ---

  test "sign_in creates an on-duty entry and logs the check-in" do
    result = ShiftManage.sign_in(person: @person, position_id: @position.id, user: @operator)

    assert_equal :success, result.status
    entry = Timesheet.find_person_on_duty(@person.id)
    assert entry
    assert_equal @position.id, entry.position_id
    assert_not entry.was_signin_forced
    log = TimesheetLog.where(timesheet_id: entry.id, action: TimesheetLog::SIGNON).first
    assert log
    assert_equal @position.id, log.data["position_id"]
  end

  test "sign_in refuses when the person is already on duty" do
    ShiftManage.sign_in(person: @person, position_id: @position.id, user: @operator)

    result = ShiftManage.sign_in(person: @person, position_id: @position.id, user: @operator)
    assert_equal :already_on_duty, result.status
  end

  test "sign_in refuses a position the person does not hold" do
    unheld = create_position!("Unheld Position")

    result = ShiftManage.sign_in(person: @person, position_id: unheld.id, user: @operator)
    assert_equal :position_not_held, result.status
    assert_nil Timesheet.find_person_on_duty(@person.id)
  end

  test "sign_in refuses a position not eligible for timesheets" do
    ineligible = create_position!("Ineligible Position", not_timesheet_eligible: true)
    grant_position(ineligible)

    result = ShiftManage.sign_in(person: @person, position_id: ineligible.id, user: @operator)
    assert_equal :position_not_eligible, result.status
  end

  test "sign_in reports blockers for an untrained person" do
    blocked = create_position!("Blocked Position", no_training_required: false)
    grant_position(blocked)

    result = ShiftManage.sign_in(person: @person, position_id: blocked.id, user: @operator)

    assert_equal :blocked, result.status
    assert result.blockers.any? { |blocker| blocker[:blocker] == Timesheet::BLOCKED_NOT_TRAINED }
    assert_nil Timesheet.find_person_on_duty(@person.id)
  end

  test "forcing a blocked sign_in requires privileges and a reason" do
    blocked = create_position!("Blocked Position", no_training_required: false)
    grant_position(blocked)

    result = ShiftManage.sign_in(person: @person, position_id: blocked.id, user: @operator,
                                 force: true, reason: "verified trained")
    assert_equal :force_not_allowed, result.status

    grant_role(@operator, Role::CAN_FORCE_SHIFT)
    # Person#has_role? consults Current when the user IS the current person,
    # exactly as in the controller flow — mirror authentication's setup.
    Current.roles_manager = RoleManager.retrieve(@operator)

    result = ShiftManage.sign_in(person: @person, position_id: blocked.id, user: @operator,
                                 force: true)
    assert_equal :missing_force_reason, result.status

    result = ShiftManage.sign_in(person: @person, position_id: blocked.id, user: @operator,
                                 force: true, reason: "verified trained")
    assert_equal :success, result.status
    entry = Timesheet.find_person_on_duty(@person.id)
    assert entry.was_signin_forced
    assert_equal "verified trained", entry.signin_force_reason
    log = TimesheetLog.where(timesheet_id: entry.id, action: TimesheetLog::SIGNON).first
    assert log.data["forced"]
  end

  # --- sign_in start_time override ---

  test "sign_in backdates the check-in to a start_time earlier today and flags the log" do
    result = ShiftManage.sign_in(person: @person, position_id: @position.id, user: @operator,
                                 start_time: "09:30")

    assert_equal :success, result.status
    entry = Timesheet.find_person_on_duty(@person.id)
    assert_equal Time.zone.local(2026, 8, 30, 9, 30, 0), entry.on_duty
    log = TimesheetLog.where(timesheet_id: entry.id, action: TimesheetLog::SIGNON).first
    assert log.data["set_time"], "a backdated check-in must be flagged in the log"
  end

  # A time later than now is last night's, not the future — but only within the
  # lookback. 13:00 read at noon would be 23 hours ago, which is out of range.
  test "sign_in refuses a start_time beyond the lookback" do
    result = ShiftManage.sign_in(person: @person, position_id: @position.id, user: @operator,
                                 start_time: "13:00")

    assert_equal :start_time_out_of_range, result.status
    assert_nil Timesheet.find_person_on_duty(@person.id)
  end

  # The burn-night case: Rollcall offers shifts that began up to four hours
  # ago, so past midnight the roster still carries last night's. Reading the
  # supplied time as "today" would put it in the future and refuse the only
  # time the operator can truthfully enter.
  test "sign_in reads a start_time later than now as last night" do
    travel_to Time.zone.local(2026, 8, 31, 0, 30, 0)

    result = ShiftManage.sign_in(person: @person, position_id: @position.id, user: @operator,
                                 start_time: "23:45")

    assert_equal :success, result.status
    assert_equal Time.zone.local(2026, 8, 30, 23, 45, 0),
                 Timesheet.find_person_on_duty(@person.id).on_duty
  end

  # A backdated check-in can land inside a shift the Ranger already finished,
  # which the on-duty guard cannot see because that shift is closed.
  test "sign_in refuses a start_time inside a shift already on record" do
    entry = Timesheet.new(person_id: @person.id, position_id: @position.id,
                          on_duty: Time.zone.local(2026, 8, 30, 8, 0, 0),
                          off_duty: Time.zone.local(2026, 8, 30, 10, 0, 0))
    entry.save!(validate: false)

    result = ShiftManage.sign_in(person: @person, position_id: @position.id, user: @operator,
                                 start_time: "09:00")

    assert_equal :start_time_overlaps, result.status
    assert_nil Timesheet.find_person_on_duty(@person.id)

    # The control: a time clear of that shift still goes through, so the
    # assertion above cannot be passing for some unrelated reason.
    assert_equal :success,
                 ShiftManage.sign_in(person: @person, position_id: @position.id,
                                     user: @operator, start_time: "11:00").status
  end

  test "sign_in refuses a malformed start_time" do
    ["9:60", "24:00", "noon", "0930", "", "12:00\n25:00"].each do |bad|
      result = ShiftManage.sign_in(person: @person, position_id: @position.id, user: @operator,
                                   start_time: bad)
      # A blank string is not an override at all -- it signs in at now.
      if bad.blank?
        assert_equal :success, result.status, "blank start_time should sign in at now"
        Timesheet.find_person_on_duty(@person.id).destroy
      else
        assert_equal :invalid_start_time, result.status, "#{bad.inspect} should be refused"
        assert_nil Timesheet.find_person_on_duty(@person.id)
      end
    end
  end

  test "sign_in evaluates blockers against the overridden start_time" do
    restricted = create_position!("Time Restricted", is_checkin_time_restricted: true,
                                                     no_training_required: true)
    grant_position(restricted)
    # A shift starting at 11:00. At the 12:00 "now" the person is inside the
    # late-check-in window; backdated to 09:00 they are far too early.
    Slot.create!(position_id: restricted.id, begins: Time.zone.local(2026, 8, 30, 11, 0, 0),
                 ends: Time.zone.local(2026, 8, 30, 17, 0, 0), description: "Day",
                 max: 5, active: true)
    Setting.find_or_create_by!(name: Setting::SHIFT_CHECK_IN_EARLY_PERIOD).update!(value: "30")
    Setting.find_or_create_by!(name: Setting::SHIFT_CHECK_IN_LATE_PERIOD).update!(value: "120")

    blocked = ShiftManage.sign_in(person: @person, position_id: restricted.id, user: @operator,
                                  start_time: "09:00")
    assert_equal :blocked, blocked.status,
                 "the blocker checks must read the overridden time, not the wall clock"

    # The control: the same check-in at the real "now" is fine. Without this
    # the assertion above would pass just as well if the position were blocked
    # for some reason having nothing to do with the time.
    assert_equal :success,
                 ShiftManage.sign_in(person: @person, position_id: restricted.id,
                                     user: @operator).status
  end

  # --- sign_off ---

  test "sign_off ends the shift and logs it" do
    entry = start_shift!

    travel 6.hours
    result = ShiftManage.sign_off(entry, user: @operator)

    assert_equal :success, result.status
    assert_not result.now_active
    assert_equal Current.time, entry.reload.off_duty
    assert TimesheetLog.where(timesheet_id: entry.id, action: TimesheetLog::SIGNOFF).exists?

    assert_equal :already_signed_off, ShiftManage.sign_off(entry, user: @operator).status
  end

  test "sign_off converts an inactive person back to active and mails the notification" do
    inactive = person(:inactive_ranger)
    grant_position(@position, person: inactive)
    entry = start_shift!(person: inactive)

    travel 6.hours
    result = nil
    assert_enqueued_emails 1 do
      result = ShiftManage.sign_off(entry, user: @operator)
    end

    assert result.now_active
    assert_equal Person::ACTIVE, inactive.reload.status
  end

  # The notice goes to the VC list from a job, where nobody is signed in, so
  # whoever ended the shift travels with it. A list belongs to no one.
  test "the conversion notice is logged under whoever ended the shift" do
    inactive = person(:inactive_ranger)
    grant_position(@position, person: inactive)
    entry = start_shift!(person: inactive)

    travel 6.hours
    ShiftManage.sign_off(entry, user: @operator)
    Current.person = nil
    perform_enqueued_jobs

    row = MailLog.find_by!(to_email: EmailAddresses::VOLUNTEER_COORDINATORS_TEAM)
    assert_equal @operator.id, row.sender_id
    assert_nil row.person_id
  end

  # --- update_position ---

  test "update_position swaps the position on an on-duty entry and audit-logs the change" do
    entry = start_shift!
    replacement = create_position!("Replacement Position")
    grant_position(replacement)

    result = ShiftManage.update_position(entry, position_id: replacement.id, user: @operator)

    assert_equal :success, result.status
    assert_equal replacement.id, entry.reload.position_id
    log = TimesheetLog.where(timesheet_id: entry.id, action: TimesheetLog::UPDATE).last
    assert_equal [@position.id, replacement.id], log.data["position_id"]
  end

  test "update_position runs the blocker checks" do
    entry = start_shift!
    blocked = create_position!("Blocked Position", no_training_required: false)
    grant_position(blocked)

    result = ShiftManage.update_position(entry, position_id: blocked.id, user: @operator)

    assert_equal :blocked, result.status
    assert_equal @position.id, entry.reload.position_id
  end

  test "update_position refuses an off-duty entry" do
    entry = start_shift!
    ShiftManage.sign_off(entry, user: @operator)

    result = ShiftManage.update_position(entry.reload, position_id: @position.id, user: @operator)
    assert_equal :not_on_duty, result.status
  end

  # --- resignin ---

  test "resignin resumes an accidentally ended shift" do
    entry = start_shift!
    travel 2.hours
    ShiftManage.sign_off(entry, user: @operator)

    result = ShiftManage.resignin(entry.reload)

    assert_equal :success, result.status
    assert_nil entry.reload.off_duty
    update_log = TimesheetLog.where(timesheet_id: entry.id, action: TimesheetLog::UPDATE).last
    assert update_log.data.key?("off_duty")
  end

  test "resignin refuses when the person is already on another shift" do
    entry = start_shift!
    travel 2.hours
    ShiftManage.sign_off(entry, user: @operator)
    start_shift!

    result = ShiftManage.resignin(entry.reload)

    assert_equal :already_on_duty, result.status
    assert_not_nil entry.reload.off_duty
  end

  test "resignin refuses an entry that has not ended" do
    entry = start_shift!

    assert_equal :not_signed_off, ShiftManage.resignin(entry).status
  end

  test "recently_signed_off_entry finds only a shift ended within the window" do
    entry = start_shift!
    travel 2.hours
    ShiftManage.sign_off(entry, user: @operator)

    assert_equal entry.id, ShiftManage.recently_signed_off_entry(@person)&.id

    travel 2.hours
    assert_nil ShiftManage.recently_signed_off_entry(@person)
  end

  # --- delete_mistake ---

  test "delete_mistake removes the entry and logs the accidental creation" do
    entry = start_shift!

    result = ShiftManage.delete_mistake(entry)

    assert_equal :success, result.status
    assert_nil Timesheet.find_by(id: entry.id)
    assert TimesheetLog.where(timesheet_id: entry.id, action: TimesheetLog::DELETE_MISTAKE).exists?
  end

  # --- position_options ---

  test "position_options filters trainings and ineligible positions and promotes the dirt positions" do
    dirt = create_position!("Dirt", id: Position::DIRT)
    shiny = create_position!("Dirt - Shiny Penny", id: Position::DIRT_SHINY_PENNY)
    trainer = create_position!("Dirt Trainer", type: Position::TYPE_TRAINING)
    training = create_position!("Green Dot Training", type: Position::TYPE_TRAINING)
    ineligible = create_position!("Ineligible Position", not_timesheet_eligible: true)
    [dirt, shiny, trainer, training, ineligible].each { |position| grant_position(position) }

    titles = ShiftManage.position_options(@person, self_serve: false).map(&:title)

    assert_equal ["Dirt - Shiny Penny", "Dirt"], titles.first(2)
    assert_includes titles, "Dirt Trainer"
    assert_not_includes titles, "Green Dot Training"
    assert_not_includes titles, "Ineligible Position"
  end

  test "position_options offers only blocker-free positions on self-serve pages" do
    blocked = create_position!("Blocked Position", no_training_required: false)
    grant_position(blocked)

    self_serve_titles = ShiftManage.position_options(@person, self_serve: true).map(&:title)
    assert_includes self_serve_titles, "Sunrise Patrol"
    assert_not_includes self_serve_titles, "Blocked Position"

    admin_titles = ShiftManage.position_options(@person, self_serve: false).map(&:title)
    assert_includes admin_titles, "Blocked Position"
  end

  test "position_options floats the self-managed positions when promoted" do
    nvo = create_position!("NVO Ranger", id: Position::NVO_RANGER)
    dpw = create_position!("DPW Ranger", id: Position::DPW_RANGER)
    grant_position(nvo)
    grant_position(dpw)

    titles = ShiftManage.position_options(@person, self_serve: true, promote_self: true).map(&:title)
    assert_equal ["NVO Ranger", "DPW Ranger"], titles.first(2)
  end

  # --- training_passed? ---

  test "training_passed? counts echelon status as passed" do
    assert ShiftManage.training_passed?(person(:echelon_ranger))
    assert_not ShiftManage.training_passed?(@person)
  end

  private

  # A position with no training requirement checks in cleanly.
  def create_position!(title, id: nil, **attrs)
    attrs = { title: title, active: true, no_training_required: true }.merge(attrs)
    attrs[:id] = id if id
    Position.create!(attrs)
  end

  def grant_position(position, person: @person)
    PersonPosition.find_or_create_by!(person_id: person.id, position_id: position.id)
  end

  def start_shift!(person: @person, position: @position)
    result = ShiftManage.sign_in(person: person, position_id: position.id, user: @operator)
    assert_equal :success, result.status
    result.entry
  end
end
