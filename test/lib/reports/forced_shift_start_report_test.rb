# frozen_string_literal: true

require "test_helper"

# The blocker payloads the controller test cannot reach cleanly: the pre-2025
# format, a forced start whose audit log is gone, and the order the rows read in.
class ForcedShiftStartReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2031

  setup do
    @now = Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    travel_to @now
    Current.reset

    @position = positions(:ood_position)
    @person = person(:active_ranger)
    @forcer = person(:echelon_ranger)
  end

  teardown do
    travel_back
    Current.reset
  end

  def create_forced(person: @person, on_duty: @now, reason: "records not entered yet")
    Timesheet.create!(person:, position: @position, on_duty:,
                      was_signin_forced: true, signin_force_reason: reason,
                      additional_notes: "test shift")
  end

  def log_force(timesheet, data, creator: @forcer)
    TimesheetLog.create!(action: TimesheetLog::SIGNON, person_id: timesheet.person_id,
                         create_person_id: creator.id, timesheet_id: timesheet.id,
                         data:, year: YEAR, created_at: @now)
  end

  test "a modern forced start carries its blockers, its forcer, and its reason" do
    timesheet = create_forced
    log_force(timesheet, { "forced" => true,
                           "blockers" => [{ "blocker" => Timesheet::BLOCKED_TOO_LATE,
                                            "distance" => 130, "cutoff" => 15 }] })

    entry = ForcedShiftStartReport.execute(year: YEAR).sole

    assert_equal @person.callsign, entry.callsign
    assert_equal @position.title, entry.position_title
    assert_equal @forcer.id, entry.forced_by_id
    assert_equal @forcer.callsign, entry.forced_by.callsign
    assert_equal "records not entered yet", entry.reason
    assert_equal Timesheet::BLOCKED_TOO_LATE, entry.blockers.sole["blocker"]
  end

  # The pre-2025 shape: `forced` is the blocker itself rather than `true`.
  # TimesheetLog#decode_data owns the conversion -- the report must not be
  # converting it a second time, and must not be skipping it either.
  test "a pre-2025 forced start is converted to the modern blocker shape" do
    timesheet = create_forced
    log_force(timesheet, { "forced" => { "reason" => "untrained",
                                         "position_id" => Position::TRAINING } })

    blocker = ForcedShiftStartReport.execute(year: YEAR).sole.blockers.sole

    assert_equal Timesheet::BLOCKED_NOT_TRAINED, blocker["blocker"]
    assert_equal Position::TRAINING, blocker.dig("position", "id")
  end

  test "the pre-2025 burn perimeter blocker keeps its five year window" do
    timesheet = create_forced
    log_force(timesheet, { "forced" => { "reason" => "no-burn-perimeter-exp" } })

    blocker = ForcedShiftStartReport.execute(year: YEAR).sole.blockers.sole

    assert_equal Timesheet::BLOCKED_NO_BURN_PERIMETER_EXP, blocker["blocker"]
    assert_equal 5, blocker["within_years"]
  end

  # The timesheet says the start was forced; only the log says what was
  # overridden. With no log the report reports no blockers rather than
  # inventing one, and the row still appears -- it is the row most worth seeing.
  test "a forced start with no audit log is still listed, with no blockers" do
    create_forced

    entry = ForcedShiftStartReport.execute(year: YEAR).sole

    assert_empty entry.blockers
    assert_nil entry.forced_by_id
    assert_nil entry.forced_by
  end

  # Non-forced logs sit beside the forced one on the same timesheet. Picking the
  # first log of the timesheet rather than the first forced log would attribute
  # the force to whoever signed the ranger off.
  test "an unforced log on the same timesheet is not mistaken for the force" do
    timesheet = create_forced
    TimesheetLog.create!(action: TimesheetLog::SIGNON, person_id: timesheet.person_id,
                         create_person_id: @person.id, timesheet_id: timesheet.id,
                         data: { "position_id" => @position.id }, year: YEAR, created_at: @now)
    log_force(timesheet, { "forced" => true,
                           "blockers" => [{ "blocker" => Timesheet::BLOCKED_NO_EMPLOYEE_ID }] })

    entry = ForcedShiftStartReport.execute(year: YEAR).sole

    assert_equal @forcer.id, entry.forced_by_id
    assert_equal Timesheet::BLOCKED_NO_EMPLOYEE_ID, entry.blockers.sole["blocker"]
  end

  test "rows read in callsign order regardless of case, then by shift start" do
    late = create_forced(on_duty: @now)
    early = create_forced(on_duty: @now - 3.hours)
    other = create_forced(person: @forcer)
    @person.update_columns(callsign: "zebra")
    @forcer.update_columns(callsign: "Aardvark")

    entries = ForcedShiftStartReport.execute(year: YEAR)

    assert_equal [other.id, early.id, late.id], entries.map(&:timesheet_id)
  end

  test "only the chosen year is reported, and unforced starts never are" do
    create_forced(on_duty: Time.zone.local(YEAR - 1, 8, 26, 12, 0, 0))
    Timesheet.create!(person: @person, position: @position, on_duty: @now,
                      additional_notes: "ordinary shift")
    forced = create_forced

    entries = ForcedShiftStartReport.execute(year: YEAR)

    assert_equal [forced.id], entries.map(&:timesheet_id)
  end

  test "no forced starts in the year is an empty list, not an error" do
    assert_empty ForcedShiftStartReport.execute(year: YEAR)
  end
end
