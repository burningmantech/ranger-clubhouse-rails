# frozen_string_literal: true

require "test_helper"

class FlakeReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include TrainingSlotTestHelper

  # Clear of the 2025/2026 fixture data.
  YEAR = 2031

  setup do
    @now = Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    travel_to @now

    @ood = positions(:ood_position)     # "OOD (Officer of the Day)"
    @mentor = positions(:mentor_lead)   # "Mentor Lead"
    @ranger = person(:active_ranger)
    @other = person(:echelon_ranger)
    @third = person(:inactive_ranger)

    # 06:00 - 18:00, spanning @now.
    @slot = create_slot(@ood, begins: @now - 6.hours, ends: @now + 6.hours)
  end

  teardown { travel_back }

  def sign_up(person, slot = @slot)
    PersonSlot.create!(person:, slot:)
  end

  # Timesheet#associate_slot links a new sign-on to a matching slot by itself,
  # so the linkage is set afterwards to exactly what the test asked for --
  # including nil, which is the shape a third of the real rows have.
  def create_timesheet(person, position, on_duty:, off_duty: nil, slot: nil)
    timesheet = Timesheet.create!(person:, position:, on_duty:, off_duty:,
                                  additional_notes: "test shift")
    timesheet.update_columns(slot_id: slot&.id)
    timesheet
  end

  def detail_for(position = @ood, year: YEAR)
    FlakeReport.position(year:, position:)
  end

  def only_slot_detail(position = @ood)
    detail_for(position).slot_details.sole
  end

  # --- Flakes -------------------------------------------------------------

  test "a sign-up with a timesheet linked to the slot appears nowhere" do
    sign_up(@ranger)
    create_timesheet(@ranger, @ood, on_duty: @slot.begins, off_duty: @slot.ends, slot: @slot)

    detail = detail_for

    assert_empty detail.slot_details
    assert_equal 0, detail.flake_count
    assert_equal 0, detail.rogue_count
    assert_equal 1, detail.clean_slot_count
  end

  test "a sign-up with no timesheet at all is a flake with no covering timesheet" do
    sign_up(@ranger)

    flake = only_slot_detail.flakes.sole

    assert_equal @ranger.callsign, flake.callsign
    assert_nil flake.timesheet
  end

  # They rangered the shift; only the slot link is missing, and roughly a
  # third of real timesheets carry none. Nothing to chase.
  test "an unlinked timesheet for this position inside the shift clears the sign-up" do
    sign_up(@ranger)
    create_timesheet(@ranger, @ood, on_duty: @slot.begins, off_duty: @slot.ends)

    detail = detail_for

    assert_empty detail.slot_details
    assert_equal 0, detail.flake_count
  end

  test "an unlinked timesheet for this position OUTSIDE the shift does not clear it" do
    sign_up(@ranger)
    create_timesheet(@ranger, @ood, on_duty: @slot.ends + 2.hours, off_duty: @slot.ends + 6.hours)

    assert_nil only_slot_detail.flakes.sole.timesheet
  end

  test "a sign-up on duty in another position reports that position" do
    sign_up(@ranger)
    create_timesheet(@ranger, @mentor, on_duty: @slot.begins + 1.hour,
                                       off_duty: @slot.begins + 3.hours)

    flake = only_slot_detail.flakes.sole

    assert_equal @mentor.title, flake.timesheet_position_title
  end

  test "a timesheet linked to another slot does not answer this slot's sign-up" do
    other_slot = create_slot(@ood, begins: @slot.ends + 1.hour, ends: @slot.ends + 6.hours)
    sign_up(@ranger)
    sign_up(@ranger, other_slot)
    create_timesheet(@ranger, @ood, on_duty: other_slot.begins, off_duty: other_slot.ends,
                                    slot: other_slot)

    flake = only_slot_detail.flakes.sole

    # Outside this shift's window, so there is nothing to report alongside.
    assert_nil flake.timesheet
  end

  test "a timesheet entirely outside the shift does not count as covering it" do
    sign_up(@ranger)
    create_timesheet(@ranger, @ood, on_duty: @slot.ends + 1.hour, off_duty: @slot.ends + 3.hours)

    assert_nil only_slot_detail.flakes.sole.timesheet
  end

  test "a timesheet overlapping either end of the shift counts as covering it" do
    sign_up(@ranger)
    create_timesheet(@ranger, @mentor, on_duty: @slot.begins - 2.hours,
                                       off_duty: @slot.begins + 10.minutes)

    assert_equal @mentor.title, only_slot_detail.flakes.sole.timesheet_position_title
  end

  # Read as running to now, a sign-on no one closed would cover every later
  # shift of the position.
  test "an open timesheet covers the shift only when it started inside it" do
    sign_up(@ranger)
    create_timesheet(@ranger, @mentor, on_duty: @slot.begins - 2.days)

    assert_nil only_slot_detail.flakes.sole.timesheet
  end

  test "an open timesheet started during the shift covers it" do
    sign_up(@ranger)
    create_timesheet(@ranger, @mentor, on_duty: @slot.begins + 1.hour)

    assert_equal @mentor.title, only_slot_detail.flakes.sole.timesheet_position_title
  end

  # An hour of this position beats a full shift of another one: the sign-up
  # was honored, however briefly.
  test "a short same-position timesheet clears the sign-up despite a longer one elsewhere" do
    sign_up(@ranger)
    create_timesheet(@ranger, @mentor, on_duty: @slot.begins, off_duty: @slot.ends)
    create_timesheet(@ranger, @ood, on_duty: @slot.begins + 2.hours,
                                    off_duty: @slot.begins + 3.hours)

    assert_empty detail_for.slot_details
  end

  # Overlapping slots of one position are how shift changes are scheduled, so
  # the sibling shift's timesheet is this position inside this shift's hours.
  test "a timesheet linked to a sibling shift of this position clears the sign-up" do
    sibling = create_slot(@ood, begins: @slot.begins - 2.hours, ends: @slot.begins + 4.hours)
    sign_up(@ranger)
    sign_up(@ranger, sibling)
    create_timesheet(@ranger, @ood, on_duty: sibling.begins, off_duty: sibling.ends,
                                    slot: sibling)

    assert_empty detail_for.slot_details
  end

  # The previous shift signing off at the moment this one starts is the
  # standard handover, not twelve hours of attendance.
  test "a timesheet ending exactly when the shift begins does not cover it" do
    sign_up(@ranger)
    create_timesheet(@ranger, @ood, on_duty: @slot.begins - 6.hours, off_duty: @slot.begins)

    assert_nil only_slot_detail.flakes.sole.timesheet
  end

  test "a timesheet starting exactly when the shift ends does not cover it" do
    sign_up(@ranger)
    create_timesheet(@ranger, @ood, on_duty: @slot.ends, off_duty: @slot.ends + 6.hours)

    assert_nil only_slot_detail.flakes.sole.timesheet
  end

  # An open sheet runs to the shift's end, so it beats a token closed one --
  # scoring it at its sign-on instant made it lose every tie.
  test "a still-open timesheet outranks a brief closed one" do
    sign_up(@ranger)
    create_timesheet(@ranger, @mentor, on_duty: @slot.begins, off_duty: @slot.begins + 15.minutes)
    create_timesheet(@ranger, @mentor, on_duty: @slot.begins + 1.hour)

    flake = only_slot_detail.flakes.sole

    assert_nil flake.timesheet.off_duty
    assert_equal @slot.begins + 1.hour, flake.timesheet.on_duty
  end

  # --- Rogues -------------------------------------------------------------

  test "a timesheet linked to the slot without a sign-up is a rogue" do
    create_timesheet(@other, @ood, on_duty: @slot.begins, off_duty: @slot.ends, slot: @slot)

    rogue = only_slot_detail.rogues.sole

    assert_equal @other.callsign, rogue.callsign
    assert_equal @slot.ends, rogue.timesheet.off_duty
  end

  # The slot link is the join, so a rogue's timesheet can be for any position
  # -- but the row has to name it, or it reads as this position's shift.
  test "a rogue's timesheet for another position names that position" do
    create_timesheet(@other, @mentor, on_duty: @slot.begins, off_duty: @slot.ends, slot: @slot)

    rogue = only_slot_detail.rogues.sole

    assert_equal @other.callsign, rogue.callsign
    assert_equal @mentor.title, rogue.position_title
    assert_not rogue.outside_shift
  end

  test "a rogue's timesheet for this position names no position" do
    create_timesheet(@other, @ood, on_duty: @slot.begins, off_duty: @slot.ends, slot: @slot)

    assert_nil only_slot_detail.rogues.sole.position_title
  end

  # Nothing filters rogues by time -- the link is the definition -- so a
  # timesheet linked to a shift it never overlapped must say so.
  test "a rogue whose timesheet falls outside the shift is marked" do
    create_timesheet(@other, @ood, on_duty: @slot.ends + 2.hours,
                                   off_duty: @slot.ends + 6.hours, slot: @slot)

    assert only_slot_detail.rogues.sole.outside_shift
  end

  # timesheet.slot_id has no unique index, so signing off and back on during a
  # shift produces two rows against one slot. The index badge and the page it
  # links to have to agree on how many that is.
  test "two timesheets on one slot count as two rogues on both pages" do
    create_timesheet(@other, @ood, on_duty: @slot.begins, off_duty: @slot.begins + 1.hour,
                                   slot: @slot)
    create_timesheet(@other, @ood, on_duty: @slot.begins + 2.hours,
                                   off_duty: @slot.ends, slot: @slot)

    ood = FlakeReport.summary(year: YEAR).positions.find { |p| p.position_id == @ood.id }

    assert_equal 2, detail_for.rogue_count
    assert_equal 2, only_slot_detail.rogues.size
    assert_equal 2, ood.rogue_count
  end

  test "an unlinked timesheet during the shift is not a rogue" do
    create_timesheet(@other, @ood, on_duty: @slot.begins, off_duty: @slot.ends)

    assert_empty detail_for.slot_details
  end

  # --- Scanned set --------------------------------------------------------

  # Attendance at a training session is recorded on trainee_status, never as a
  # timesheet, so every trainee in the room would otherwise be a flake.
  test "training slots are excluded" do
    training = Position.create!(id: 99_414, title: "In-Person Training",
                                type: Position::TYPE_TRAINING)
    sign_up(@ranger, create_slot(training, begins: @now - 1.hour, ends: @now + 1.hour))

    assert_equal 0, detail_for(training).slot_count
    assert_nil FlakeReport.summary(year: YEAR).positions
                          .find { |position| position.position_id == training.id }
  end

  # Trainer positions carry the Training type too, and the whole type is out
  # of scope by decree -- not just the trainee sessions.
  test "trainer slots are excluded along with the rest of the Training type" do
    trainer = Position.create!(id: 99_415, title: "Green Dot Trainer",
                               type: Position::TYPE_TRAINING)
    sign_up(@ranger, create_slot(trainer, begins: @now - 3.hours, ends: @now - 1.hour))

    assert_equal 0, detail_for(trainer).slot_count
    assert_nil FlakeReport.summary(year: YEAR).positions
                          .find { |position| position.position_id == trainer.id }
  end

  # ShiftManage refuses check-in on these, so their sign-ups could never clear.
  test "positions no one can go on duty for are excluded" do
    ineligible = Position.create!(id: 99_416, title: "Paperwork Only",
                                  not_timesheet_eligible: true)
    sign_up(@ranger, create_slot(ineligible, begins: @now - 3.hours, ends: @now - 1.hour))

    assert_equal 0, detail_for(ineligible).slot_count
    assert_nil FlakeReport.summary(year: YEAR).positions
                          .find { |position| position.position_id == ineligible.id }
  end

  # No one has failed to show for a shift that has not begun.
  test "shifts that have not started yet are excluded" do
    sign_up(@ranger, create_slot(@ood, begins: @now + 2.hours, ends: @now + 8.hours))

    assert_equal 1, detail_for.slot_count
    assert_equal 0, detail_for.flake_count
  end

  test "inactive slots are excluded" do
    @slot.update!(active: false)
    sign_up(@ranger)

    detail = detail_for

    assert_equal 0, detail.slot_count
    assert_empty detail.slot_details
  end

  test "another year's slots are excluded" do
    sign_up(@ranger)

    assert_equal 0, detail_for(year: YEAR - 1).slot_count
  end

  # --- Summary ------------------------------------------------------------

  test "the summary counts shifts, flakes, and rogues per position" do
    sign_up(@ranger)
    sign_up(@other)
    create_timesheet(@other, @ood, on_duty: @slot.begins, off_duty: @slot.ends, slot: @slot)
    create_timesheet(@third, @ood, on_duty: @slot.begins, off_duty: @slot.ends, slot: @slot)

    mentor_slot = create_slot(@mentor, begins: @now - 2.hours, ends: @now + 2.hours)
    sign_up(@ranger, mentor_slot)

    summary = FlakeReport.summary(year: YEAR)
    ood = summary.positions.find { |position| position.position_id == @ood.id }
    mentor = summary.positions.find { |position| position.position_id == @mentor.id }

    assert_equal 1, ood.slot_count
    assert_equal 1, ood.flake_count   # @ranger signed up, never linked
    assert_equal 1, ood.rogue_count   # @third linked, never signed up
    assert_equal 1, mentor.flake_count
    assert_equal 2, summary.slot_count
    assert_equal 2, summary.flake_count
    assert_equal 1, summary.rogue_count
  end

  test "the summary lists positions by title" do
    create_slot(@mentor, begins: @now - 2.hours, ends: @now + 2.hours)

    titles = FlakeReport.summary(year: YEAR).positions.map(&:title)

    assert_equal titles.sort_by(&:downcase), titles
  end

  # A shift no one signed up for and no one rangered produces no row at all,
  # so it needs its own count -- otherwise it reads as a clean shift.
  test "shifts with no sign-ups are counted apart from the clean ones" do
    honored = create_slot(@ood, begins: @now - 10.hours, ends: @now - 8.hours)
    sign_up(@ranger, honored)
    create_timesheet(@ranger, @ood, on_duty: honored.begins, off_duty: honored.ends,
                                    slot: honored)

    detail = detail_for
    ood = FlakeReport.summary(year: YEAR).positions.find { |p| p.position_id == @ood.id }

    # @slot from setup has no sign-ups at all; honored has one, kept.
    assert_equal 1, detail.unstaffed_slot_count
    assert_equal 1, detail.clean_slot_count
    assert_empty detail.slot_details
    assert_equal 1, ood.unstaffed_slot_count
    assert_equal 1, FlakeReport.summary(year: YEAR).unstaffed_slot_count
  end

  # The three buckets are disjoint: a shift no one signed up for that somebody
  # rangered anyway is flagged as a rogue, not counted as unstaffed.
  test "a shift with no sign-ups but a rogue counts as flagged, not unstaffed" do
    create_timesheet(@other, @ood, on_duty: @slot.begins, off_duty: @slot.ends, slot: @slot)

    detail = detail_for

    assert_equal 1, detail.slot_details.size
    assert_equal 0, detail.unstaffed_slot_count
    assert_equal 0, detail.clean_slot_count
  end

  test "the summary reports a year with no slots as empty" do
    summary = FlakeReport.summary(year: YEAR - 1)

    assert_empty summary.positions
    assert_equal 0, summary.slot_count
  end

  # --- Row shape ----------------------------------------------------------

  test "rows sort by callsign within a shift" do
    [@third, @ranger, @other].each { |person| sign_up(person) }

    callsigns = only_slot_detail.flakes.map(&:callsign)

    assert_equal callsigns.sort_by(&:downcase), callsigns
  end

  test "the signed-up count on a shift comes from the sign-ups, not slot.signed_up" do
    sign_up(@ranger)
    sign_up(@other)
    @slot.update!(signed_up: 99)

    assert_equal 2, only_slot_detail.signup_count
  end
end
