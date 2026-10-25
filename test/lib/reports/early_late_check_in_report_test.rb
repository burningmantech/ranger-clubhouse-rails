# frozen_string_literal: true

require "test_helper"

# The window rules, which the controller test cannot reach cleanly: which
# check-ins are flagged, which shift a flag is measured against when two are in
# reach, and who is forgiven.
class EarlyLateCheckInReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include TrainingSlotTestHelper

  # Clear of the 2025/2026 fixture data.
  YEAR = 2031

  EARLY_PERIOD = 60
  LATE_PERIOD = 30

  setup do
    @now = Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    travel_to @now

    @ood = positions(:ood_position)
    @mentor = positions(:mentor_lead)
    @ranger = person(:active_ranger)
    @other = person(:echelon_ranger)

    set_periods(EARLY_PERIOD, LATE_PERIOD)

    # Noon to 20:00. Check in before 11:00 and it is early; after 12:30, late.
    @slot = create_slot(@ood, begins: @now, ends: @now + 8.hours)
  end

  teardown { travel_back }

  def set_periods(early, late)
    Setting.find_or_create_by!(name: Setting::SHIFT_CHECK_IN_EARLY_PERIOD)
           .update!(value: early.to_s)
    Setting.find_or_create_by!(name: Setting::SHIFT_CHECK_IN_LATE_PERIOD)
           .update!(value: late.to_s)
  end

  def check_in(on_duty, person: @ranger, position: @ood, off_duty: nil)
    Timesheet.create!(person:, position:, on_duty:, off_duty:,
                      additional_notes: "test shift")
  end

  def entries(year: YEAR) = EarlyLateCheckInReport.execute(year:).entries

  def only_entry(...) = entries(...).sole

  # --- The window ---------------------------------------------------------

  test "a check-in more than the early period before the shift is flagged early" do
    check_in(@now - 90.minutes)

    entry = only_entry

    assert_equal :early, entry.type
    assert_equal 90, entry.distance
    assert_equal @ranger.callsign, entry.callsign
    assert_equal @ood.title, entry.position_title
    assert_equal @slot.description, entry.slot_description
  end

  test "a check-in inside the early period is not flagged" do
    check_in(@now - 30.minutes)

    assert_empty entries
  end

  test "a check-in more than the late period after the shift began is flagged late" do
    check_in(@now + 1.hour)

    entry = only_entry

    assert_equal :late, entry.type
    assert_equal 60, entry.distance
  end

  test "a check-in inside the late period is not flagged" do
    check_in(@now + 20.minutes)

    assert_empty entries
  end

  # Upstream reports whole minutes, rounded away from the limit, so a check-in
  # part way through a minute cannot read as nearer the shift than it was.
  test "a distance is rounded up to the whole minute" do
    check_in(@now - 90.minutes - 30.seconds)

    assert_equal 91, only_entry.distance
  end

  # --- What is out of scope -----------------------------------------------

  test "a position with no scheduled shifts is never flagged" do
    check_in(@now - 90.minutes, position: @mentor)

    assert_empty entries
  end

  test "a cancelled shift is not a window to be outside of" do
    @slot.update!(active: false)
    check_in(@now - 90.minutes)

    assert_empty entries
  end

  test "a position that keeps no timesheets is not reported" do
    @ood.update!(not_timesheet_eligible: true)
    check_in(@now - 90.minutes)

    assert_empty entries
  end

  test "another year's check-in is not reported" do
    check_in(@now - 90.minutes)

    assert_empty entries(year: YEAR - 1)
  end

  # --- Forgiveness --------------------------------------------------------

  # The burn night case: the perimeter drops and everyone on it goes straight
  # onto another position, hours after that position's shift began.
  test "a ranger who came off another shift within the hour is forgiven" do
    check_in(@now - 3.hours, position: @mentor, off_duty: @now + 50.minutes)
    check_in(@now + 1.hour)

    assert_empty entries
  end

  test "a ranger whose last shift ended over an hour ago is still flagged" do
    check_in(@now - 3.hours, position: @mentor, off_duty: @now - 30.minutes)
    check_in(@now + 1.hour)

    assert_equal :late, only_entry.type
  end

  test "another ranger's shift does not forgive this one" do
    check_in(@now - 3.hours, person: @other, position: @mentor, off_duty: @now + 50.minutes)
    check_in(@now + 1.hour)

    assert_equal @ranger.callsign, only_entry.callsign
  end

  # --- Too late for one shift and too early for the next ------------------

  # Under two hours into the running shift, the check-in belongs to it.
  test "a check-in under two hours into the running shift is late for it" do
    create_slot(@ood, begins: @now + 4.hours, ends: @now + 12.hours)
    check_in(@now + 1.hour)

    entry = only_entry

    assert_equal :late, entry.type
    assert_equal 60, entry.distance
  end

  # Past that, inside the two hours before the next shift, it belongs to the
  # next one instead.
  test "a check-in inside the two hours before the next shift is early for it" do
    create_slot(@ood, begins: @now + 4.hours, ends: @now + 12.hours)
    check_in(@now + 2.hours + 30.minutes)

    entry = only_entry

    assert_equal :early, entry.type
    assert_equal 90, entry.distance
  end

  # Adrift between the two: too far into the running shift to be its late start,
  # too far from the next to be its early one. Upstream calls it late.
  test "a check-in adrift between two shifts is late for the running one" do
    create_slot(@ood, begins: @now + 6.hours, ends: @now + 12.hours)
    check_in(@now + 2.hours + 30.minutes)

    entry = only_entry

    assert_equal :late, entry.type
    assert_equal 150, entry.distance
  end

  # --- Either check switched off ------------------------------------------

  test "a blank early period switches off the early check" do
    set_periods(0, LATE_PERIOD)
    check_in(@now - 90.minutes)

    assert_empty entries
  end

  test "a blank late period switches off the late check" do
    set_periods(EARLY_PERIOD, 0)
    check_in(@now + 1.hour)

    assert_empty entries
  end

  test "a blank late period leaves the early check alone" do
    set_periods(EARLY_PERIOD, 0)
    check_in(@now - 90.minutes)

    assert_equal :early, only_entry.type
  end

  # --- How the check-in was made ------------------------------------------

  test "a check-in made through the bulk uploader says so" do
    timesheet = check_in(@now - 90.minutes)
    TimesheetLog.create!(action: TimesheetLog::CREATED, person_id: timesheet.person_id,
                         create_person_id: @other.id, timesheet_id: timesheet.id,
                         data: { "via" => TimesheetLog::VIA_BULK_UPLOAD },
                         year: YEAR, created_at: @now)

    assert_equal TimesheetLog::VIA_BULK_UPLOAD, only_entry.via
  end

  # Starting a shift at HQ writes no creation log at all.
  test "an ordinary check-in carries no via" do
    check_in(@now - 90.minutes)

    assert_nil only_entry.via
  end

  # --- Rollups ------------------------------------------------------------

  test "the rollups count each ranger and each position, worst first" do
    check_in(@now - 90.minutes)
    check_in(@now + 1.hour)
    check_in(@now - 90.minutes, person: @other)

    report = EarlyLateCheckInReport.execute(year: YEAR)

    people = EarlyLateCheckInReport.person_totals(report.entries)

    assert_equal 3, report.entries.size
    assert_equal [@ranger.callsign, @other.callsign], people.map(&:callsign)
    assert_equal [2, 1], people.map(&:total)
    assert_equal [[@ood.title, 2]], people.first.positions.map { [it.title, it.total] }
    assert_equal [[@ood.title, 3]], report.positions.map { [it.title, it.total] }
  end

  test "the entries read in check-in order" do
    check_in(@now + 1.hour)
    check_in(@now - 90.minutes, person: @other)

    assert_equal [@other.callsign, @ranger.callsign], entries.map(&:callsign)
  end

  test "the report carries the limits it applied" do
    report = EarlyLateCheckInReport.execute(year: YEAR)

    assert_equal EARLY_PERIOD * 60, report.early_period
    assert_equal LATE_PERIOD * 60, report.late_period
    assert_predicate report, :empty?
  end
end
