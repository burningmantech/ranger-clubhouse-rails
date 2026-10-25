# frozen_string_literal: true

require "test_helper"

class OnDutyReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include TrainingSlotTestHelper

  # Clear of the 2025/2026 fixture data.
  YEAR = 2031

  setup do
    @now = Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    travel_to @now

    @ood = positions(:ood_position)         # "OOD (Officer of the Day)"
    @mentor = positions(:mentor_lead)       # "Mentor Lead"
    @ranger = person(:active_ranger)
    @other = person(:echelon_ranger)
  end

  teardown { travel_back }

  def create_timesheet(person, position, on_duty:, off_duty: nil, slot: nil)
    Timesheet.create!(person:, position:, on_duty:, off_duty:, slot:,
                      additional_notes: "test shift")
  end

  def entries_for(report, title)
    report.positions.find { |position| position.title == title }&.entries || []
  end

  # --- Right-now mode ---------------------------------------------------

  test "right-now mode lists open entries and elapsed runs to now" do
    create_timesheet(@ranger, @ood, on_duty: @now - 2.hours)
    create_timesheet(@other, @ood, on_duty: @now - 5.hours, off_duty: @now - 1.hour)

    report = OnDutyReport.execute

    assert_equal 1, report.total_people
    entry = entries_for(report, @ood.title).sole
    assert_equal @ranger.id, entry.person.id
    assert_equal 2.hours.to_i, entry.elapsed
  end

  test "positions are grouped, flagged ones first, then by title" do
    # The unflagged position has to sort first on BOTH of the orderings the sort
    # displaces, or the assertion passes without it: Mentor Lead precedes OOD by
    # title, and its earlier on_duty puts it first in the query's own order (and
    # so in group_by's insertion order) too. A 24-hour slot keeps 12 hours on
    # duty under the threshold.
    long_slot = create_slot(@mentor, begins: @now - 12.hours, ends: @now + 12.hours)
    create_timesheet(@other, @mentor, on_duty: @now - 12.hours, slot: long_slot)
    create_timesheet(@ranger, @ood, on_duty: @now - 10.hours)

    report = OnDutyReport.execute

    assert_equal [@ood.title, @mentor.title], report.positions.map(&:title)
    assert_equal 1, report.positions.first.excessive_count
    assert_equal 0, report.positions.last.excessive_count
  end

  test "positions with the same flag state fall back to title order" do
    create_timesheet(@ranger, @ood, on_duty: @now - 1.hour)
    create_timesheet(@other, @mentor, on_duty: @now - 2.hours)

    # Neither is flagged, and the later-starting OOD would come first by
    # insertion order, so only the title tiebreak can produce this.
    assert_equal [@mentor.title, @ood.title], OnDutyReport.execute.positions.map(&:title)
  end

  # --- The excessive-duration flag ---------------------------------------

  test "the flag needs to run PAST 1.5x, not reach it" do
    exactly = create_timesheet(@ranger, @ood,
                               on_duty: @now - (OnDutyReport::DEFAULT_SHIFT_DURATION * 1.5).to_i.seconds)

    assert_not entries_for(OnDutyReport.execute, @ood.title).sole.excessive?

    exactly.update!(on_duty: exactly.on_duty - 1.second, additional_notes: "nudge")

    assert entries_for(OnDutyReport.execute, @ood.title).sole.excessive?
  end

  test "an attached slot sets the normal duration, and over-by is measured against it" do
    slot = create_slot(@ood, begins: @now - 4.hours, ends: @now - 2.hours) # 2 hours
    create_timesheet(@ranger, @ood, on_duty: @now - 4.hours, slot:)

    entry = entries_for(OnDutyReport.execute, @ood.title).sole

    assert_equal 2.hours.to_i, entry.normal_duration
    assert entry.excessive?
    assert_equal 2.hours.to_i, entry.excessive_duration
    # 4h against a 2h shift is 200% of it -- 100% over. Truncated, as upstream.
    assert_equal 100, entry.excessive_percentage
  end

  test "no slot falls back to six hours" do
    create_timesheet(@ranger, @ood, on_duty: @now - 7.hours)

    entry = entries_for(OnDutyReport.execute, @ood.title).sole

    assert_equal OnDutyReport::DEFAULT_SHIFT_DURATION, entry.normal_duration
    assert_not entry.excessive? # 7h is under 9h
    assert_equal 1, OnDutyReport.execute.no_shift_count
  end

  test "a zero-duration slot is treated as unscheduled rather than dividing by zero" do
    # Validation will not let one be built, so this is a legacy row: upstream
    # divides by its duration and would die.
    slot = create_slot(@ood, begins: @now - 4.hours, ends: @now - 2.hours)
    slot.update_column(:duration, 0)
    create_timesheet(@ranger, @ood, on_duty: @now - 4.hours, slot:)

    entry = entries_for(OnDutyReport.execute, @ood.title).sole

    assert_equal OnDutyReport::DEFAULT_SHIFT_DURATION, entry.normal_duration
    assert_not entry.excessive?
  end

  test "excessive_only drops unflagged entries and the positions holding only those" do
    create_timesheet(@other, @mentor, on_duty: @now - 1.hour)
    create_timesheet(@ranger, @ood, on_duty: @now - 10.hours)

    report = OnDutyReport.execute(excessive_only: true)

    assert_equal [@ood.title], report.positions.map(&:title)
    assert_equal 1, report.total_people
  end

  # --- Point-in-time mode -------------------------------------------------

  test "the window catches entries spanning the instant and nothing else" do
    at = @now - 6.hours
    spanning = create_timesheet(@ranger, @ood, on_duty: at - 1.hour, off_duty: at + 1.hour)
    ended_before = create_timesheet(@other, @ood, on_duty: at - 3.hours, off_duty: at - 1.hour)

    ids = OnDutyReport.execute(duty_date: at).entries.map { |entry| entry.timesheet.id }

    assert_includes ids, spanning.id
    assert_not_includes ids, ended_before.id
  end

  test "an entry that is still open shows up in the point-in-time window" do
    at = @now - 6.hours
    still_open = create_timesheet(@ranger, @ood, on_duty: at - 1.hour)

    entry = OnDutyReport.execute(duty_date: at).entries.sole

    # Upstream's `off_duty >= T` never matched NULL, so this row vanished.
    assert_equal still_open.id, entry.timesheet.id
  end

  test "a closed entry's elapsed is measured to the duty date, not to its own end" do
    at = @now - 6.hours
    # Signed on an hour before the instant asked about, signed out long after.
    create_timesheet(@ranger, @ood, on_duty: at - 1.hour, off_duty: at + 9.hours)

    entry = OnDutyReport.execute(duty_date: at).entries.sole

    # Counting the whole ten-hour shift flagged them for nine hours they had
    # not yet been on duty.
    assert_equal 1.hour.to_i, entry.elapsed
    assert_not entry.excessive?
  end

  test "a sign-on stamped in the future reads zero, not a negative clock" do
    # Only reachable in right-now mode: the point-in-time window bounds on_duty
    # above by the instant asked about, but on_duty_now does not.
    create_timesheet(@ranger, @ood, on_duty: @now + 2.hours)

    entry = OnDutyReport.execute.entries.sole

    # A negative reached hour_minute_format as "-2:30" for -1.5 hours.
    assert_equal 0, entry.elapsed
    assert_not entry.excessive?
  end

  test "a still-open shift that began in the previous year is still on duty" do
    began = Time.zone.local(YEAR - 1, 12, 31, 22, 0, 0)
    still_open = create_timesheet(@ranger, @ood, on_duty: began)

    entry = OnDutyReport.execute(duty_date: Time.zone.local(YEAR, 1, 1, 0, 30, 0)).entries.sole

    assert_equal still_open.id, entry.timesheet.id
  end

  test "a duty date in the first hour of a year still finds who was on duty" do
    at = Time.zone.local(YEAR, 1, 1, 0, 30, 0)
    open_entry = create_timesheet(@ranger, @ood, on_duty: at - 15.minutes)

    # The year bound and the instant bound used to be built in different zones,
    # which made this window mutually exclusive and returned no one.
    assert_equal [open_entry.id], OnDutyReport.execute(duty_date: at).entries.map { it.timesheet.id }
  end

  test "a never-closed entry from a past event stays off the right-now board" do
    create_timesheet(@ranger, @ood, on_duty: @now - 2.years)
    current = create_timesheet(@other, @mentor, on_duty: @now - 1.hour)

    report = OnDutyReport.execute

    assert_equal [current.id], report.entries.map { it.timesheet.id }
    assert_equal 0, report.excessive_count
  end

  test "a timesheet whose position row is gone renders a placeholder, not a crash" do
    # belongs_to demands the row at creation, so delete it afterwards. There is
    # no FK, so production carries these.
    orphan_position = Position.create!(id: 99_412, title: "Gone")
    create_timesheet(@ranger, orphan_position, on_duty: @now - 1.hour)
    Position.delete(orphan_position.id)

    assert_equal ["Position #99412"], OnDutyReport.execute.positions.map(&:title)
  end

  test "an open entry's elapsed time is measured to the duty date, not to now" do
    at = @now - 6.hours
    create_timesheet(@ranger, @ood, on_duty: at - 1.hour)

    entry = OnDutyReport.execute(duty_date: at).entries.sole

    # Measuring to Current.time would read 7 hours and flag the row.
    assert_equal 1.hour.to_i, entry.elapsed
    assert_not entry.excessive?
  end

  test "the point-in-time window is scoped to the duty date's year" do
    at = @now - 6.hours
    ancient = create_timesheet(@ranger, @ood, on_duty: Time.zone.local(YEAR - 2, 8, 26, 10, 0, 0))

    ids = OnDutyReport.execute(duty_date: at).entries.map { |entry| entry.timesheet.id }

    assert_not_includes ids, ancient.id
  end
end
