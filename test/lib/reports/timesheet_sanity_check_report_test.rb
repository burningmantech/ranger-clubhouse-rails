# frozen_string_literal: true

require "test_helper"

# The eight predicates, each pinned on its own. Several of them overlap by
# design -- a two-minute entry that also ends before it starts trips two --
# so every test asserts what a check does NOT pick up as well as what it does.
class TimesheetSanityCheckReportTest < ActiveSupport::TestCase
  # A year the timesheet fixtures leave alone; they carry 2023, 2024, and 2025
  # entries, which would ride along in every count.
  YEAR = 2022

  setup do
    Rails.cache.clear
    Current.reset

    @person = person(:active_ranger)
    @other = person(:inactive_ranger)

    # Explicit ids: PROBLEM_HOURS and the Alpha check are keyed by position id,
    # and fixture ids are hashed from the label.
    @ood = Position.create!(id: Position::OOD, title: "OOD",
                            type: Position::TYPE_FRONTLINE, active: true)
    @gerlach = Position.create!(id: Position::GERLACH_PATROL, title: "Gerlach Patrol",
                                type: Position::TYPE_FRONTLINE, active: true)
    @alpha = Position.create!(id: Position::ALPHA, title: "Alpha",
                              type: Position::TYPE_FRONTLINE, active: true)
    # Deliberately absent from PROBLEM_HOURS -- the DEFAULT_MAX_HOURS case.
    @dirt = positions(:ood_position)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def august(day, hour = 12, minute = 0)
    Time.zone.local(YEAR, 8, day, hour, minute, 0)
  end

  # additional_notes is required on every Timesheet.
  def entry(position, on_duty:, off_duty:, who: @person, **attrs)
    Timesheet.create!(person: who, position:, on_duty:, off_duty:,
                      additional_notes: "test shift", **attrs)
  end

  def keys_of(summary) = summary.counts.select { |_, count| count.positive? }.keys

  def counts(year: YEAR) = TimesheetSanityCheckReport.summary(year:).counts

  def findings(check, year: YEAR)
    TimesheetSanityCheckReport.findings(year:, check:)
  end

  # --- structure ---------------------------------------------------------

  test "every check has display metadata, and every metadata key is a check" do
    # The two tables are keyed by the same symbols and live in different
    # layers. Without this they drift, and the first sign of it is a page
    # raising KeyError in front of a reader.
    meta_keys = Timesheets::SanityCheckerHelper::CHECK_META.keys
    assert_equal TimesheetSanityCheckReport::KEYS.sort, meta_keys.sort
  end

  test "every check names a band the band metadata describes" do
    band_keys = Timesheets::SanityCheckerHelper::BAND_META.keys
    assert_equal TimesheetSanityCheckReport::BANDS.sort, band_keys.sort
  end

  test "the summary counts every check but the deferred one" do
    assert_equal (TimesheetSanityCheckReport::KEYS - [:no_credits]).sort,
                 counts.keys.sort
  end

  # --- the checks --------------------------------------------------------

  test "an entry with no sign-out is still on duty and nothing else" do
    open = Timesheet.create!(person: @person, position: @dirt, on_duty: august(20),
                             additional_notes: "test shift")

    assert_equal [:on_duty], keys_of(TimesheetSanityCheckReport.summary(year: YEAR))
    assert_equal [open.id], findings(:on_duty).map(&:id)
  end

  test "an entry ending before it starts is flagged, and an open one is not" do
    backwards = backwards_entry(on_duty: august(20, 18), off_duty: august(20, 9))
    Timesheet.create!(person: @other, position: @dirt, on_duty: august(20),
                      additional_notes: "test shift")

    assert_equal [backwards.id], findings(:end_before_start).map(&:id)
  end

  test "two entries of one person running at once are one overlapping finding" do
    first = entry(@dirt, on_duty: august(20, 9), off_duty: august(20, 15))
    second = entry(@dirt, on_duty: august(20, 12), off_duty: august(20, 18))
    # Same clock, different person: no overlap.
    entry(@dirt, on_duty: august(20, 12), off_duty: august(20, 18), who: @other)

    found = findings(:overlapping)
    assert_equal 1, found.size
    assert_equal @person.id, found.first.person_id
    assert_equal [[first.id, second.id]], found.first.pairs.map { |pair| pair.map(&:id) }
  end

  test "an entry containing several later ones reports every pair" do
    # Comparing consecutive entries only would report the long entry against
    # the first short one and then the short ones against each other -- one
    # pair, and B and C invisible on every later run.
    long = entry(@dirt, on_duty: august(20, 9), off_duty: august(20, 20))
    inside = [entry(@dirt, on_duty: august(20, 10), off_duty: august(20, 11)),
              entry(@dirt, on_duty: august(20, 12), off_duty: august(20, 13)),
              entry(@dirt, on_duty: august(20, 14), off_duty: august(20, 15))]

    found = findings(:overlapping)
    assert_equal 1, found.size
    assert_equal inside.map { [long.id, _1.id] },
                 found.first.pairs.map { |pair| pair.map(&:id) }
  end

  test "back-to-back entries do not overlap" do
    entry(@dirt, on_duty: august(20, 9), off_duty: august(20, 15))
    entry(@dirt, on_duty: august(20, 15), off_duty: august(20, 18))

    assert_empty findings(:overlapping)
  end

  test "a listed position is flagged past 1.5 times its own maximum" do
    # Gerlach Patrol is 15 hours, so the flag fires past 22.5.
    flagged = entry(@gerlach, on_duty: august(20, 0), off_duty: august(21, 0))
    entry(@gerlach, on_duty: august(22, 0), off_duty: august(22, 20), who: @other)

    assert_equal [flagged.id], findings(:too_long).map(&:id)
  end

  test "an unlisted position is flagged past the default maximum, not the smallest listed one" do
    # 30 hours. Upstream's accidental fallback was the smallest PROBLEM_HOURS
    # value (15, so a 22.5 hour threshold) and would have flagged this;
    # DEFAULT_MAX_HOURS puts the line at 36.
    entry(@dirt, on_duty: august(20, 0), off_duty: august(21, 6))
    assert_empty findings(:too_long)

    # 40 hours clears the default.
    flagged = entry(@dirt, on_duty: august(23, 0), off_duty: august(24, 16), who: @other)
    assert_equal [flagged.id], findings(:too_long).map(&:id)
  end

  test "an entry far longer than its scheduled shift is flagged unless suppressed" do
    slot = create_slot(@dirt, begins: august(20, 9), ends: august(20, 13))

    flagged = entry(@dirt, on_duty: august(20, 9), off_duty: august(20, 21), slot:)
    entry(@dirt, on_duty: august(20, 9), off_duty: august(20, 21), slot:, who: @other,
                 suppress_duration_warning: true)

    assert_equal [flagged.id], findings(:too_long_for_shift).map(&:id)
  end

  test "an open entry is not flagged against its scheduled shift" do
    # It measures to now, so it would beat any slot length forever and restate
    # what "Still on duty" already says -- the rule too_long already follows.
    slot = create_slot(@dirt, begins: august(20, 9), ends: august(20, 13))
    Timesheet.create!(person: @person, position: @dirt, on_duty: august(20, 9), slot:,
                      additional_notes: "test shift")

    assert_empty findings(:too_long_for_shift)
    assert_equal 1, findings(:on_duty).size
  end

  test "an entry within 1.5 times its scheduled shift is not flagged" do
    slot = create_slot(@dirt, begins: august(20, 9), ends: august(20, 13))
    # slot: passed, or the assertion holds for the wrong reason -- an entry
    # with no shift can never be flagged by this check.
    entry(@dirt, on_duty: august(20, 9), off_duty: august(20, 14), slot:)

    assert_empty findings(:too_long_for_shift)
  end

  test "an entry attached to a zero-length shift is not flagged" do
    # Slot validates begins < ends, so this shape only arrives as legacy data.
    # The column defaults to 0, and any duration at all clears `>= 0`.
    slot = create_slot(@dirt, begins: august(20, 9), ends: august(20, 13))
    slot.update_column(:duration, 0)
    entry(@dirt, on_duty: august(20, 9), off_duty: august(20, 17), slot:)

    assert_empty findings(:too_long_for_shift)
  end

  test "a fifteen minute entry is too short and a sixteen minute one is not" do
    flagged = entry(@dirt, on_duty: august(20, 9, 0), off_duty: august(20, 9, 15))
    entry(@dirt, on_duty: august(20, 11, 0), off_duty: august(20, 11, 16), who: @other)

    assert_equal [flagged.id], findings(:too_short).map(&:id)
  end

  test "an entry that ends before it starts is not called too short" do
    # Its duration is negative, which clears a bare `<= 900`; the :shortest
    # ordering then puts a fifteen-hour-backwards entry at the top of a page
    # headed "fifteen minutes or less". It belongs to end_before_start alone.
    backwards = backwards_entry(on_duty: august(20, 18), off_duty: august(20, 9))

    assert_empty findings(:too_short)
    assert_equal [backwards.id], findings(:end_before_start).map(&:id)
  end

  test "a suppressed short entry is not flagged" do
    entry(@dirt, on_duty: august(20, 9), off_duty: august(20, 9, 5),
                 suppress_duration_warning: true)

    assert_empty findings(:too_short)
  end

  test "a second Alpha entry flags the person, and one Alpha entry does not" do
    first = entry(@alpha, on_duty: august(20, 9), off_duty: august(20, 15))
    second = entry(@alpha, on_duty: august(22, 9), off_duty: august(22, 15))
    entry(@alpha, on_duty: august(20, 9), off_duty: august(20, 15), who: @other)

    found = findings(:duplicate_alphas)
    assert_equal 1, found.size
    assert_equal @person.id, found.first.person_id
    assert_equal [first.id, second.id], found.first.entries.map(&:id)
  end

  test "an entry earning nothing is listed under no credits" do
    # No PositionCredit rows exist for these positions in this year, so every
    # entry prices at zero.
    listed = entry(@dirt, on_duty: august(20, 9), off_duty: august(20, 15))

    assert_includes findings(:no_credits).map(&:id), listed.id
  end

  test "an entry inside a credit range is not listed under no credits" do
    PositionCredit.create!(position: @dirt, start_time: august(20, 0), end_time: august(21, 0),
                           credits_per_hour: 2.0, description: "test credits")
    earning = entry(@dirt, on_duty: august(20, 9), off_duty: august(20, 15))

    assert_not_includes findings(:no_credits).map(&:id), earning.id
  end

  # --- band arithmetic ---------------------------------------------------

  test "an entry caught by two review checks counts once toward entries to review" do
    slot = create_slot(@dirt, begins: august(20, 9), ends: august(20, 13))
    # 40 hours against a 4 hour shift: both too_long and too_long_for_shift.
    entry(@dirt, on_duty: august(20, 9), off_duty: august(22, 1), slot:)

    summary = TimesheetSanityCheckReport.summary(year: YEAR)
    assert_equal 1, summary.counts[:too_long]
    assert_equal 1, summary.counts[:too_long_for_shift]
    assert_equal 1, summary.entries_to_review
  end

  test "one person caught by two contact checks counts once toward rangers to contact" do
    Timesheet.create!(person: @person, position: @dirt, on_duty: august(20),
                      additional_notes: "test shift")
    backwards_entry(on_duty: august(22, 18), off_duty: august(22, 9))

    assert_equal 1, TimesheetSanityCheckReport.summary(year: YEAR).rangers_to_contact
  end

  test "a clean year counts zero everywhere" do
    summary = TimesheetSanityCheckReport.summary(year: YEAR)

    assert_empty keys_of(summary)
    assert_equal 0, summary.rangers_to_contact
    assert_equal 0, summary.entries_to_review
    # Every check on the board is the denominator, and the deferred one is
    # never clear -- it has not been run. A clean year reads "7 of 8", not
    # "7 of 7" above eight rows.
    assert_equal TimesheetSanityCheckReport::KEYS.size, summary.checked_count
    assert_equal summary.checked_count - 1, summary.clear_count
  end

  private

  # Timesheet validates off_duty >= on_duty, so an entry that ends before it
  # starts cannot be made through the model at all. The check exists for rows
  # that predate the validation -- which is why the state has to be written
  # past it here.
  def backwards_entry(on_duty:, off_duty:, who: @person)
    row = entry(@dirt, on_duty:, off_duty: on_duty, who:)
    row.update_columns(off_duty:)
    row
  end

  def create_slot(position, begins:, ends:, description: "Test shift")
    Slot.create!(position:, begins:, ends:, description:,
                 max: 5, active: true, begins_year: begins.year)
  end
end
