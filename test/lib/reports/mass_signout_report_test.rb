# frozen_string_literal: true

require "test_helper"

class MassSignoutReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2031

  setup do
    Rails.cache.clear
    Current.reset

    @now = Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    travel_to @now

    @ranger = person(:active_ranger)
    @ood = positions(:ood_position)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  def create_timesheet(on_duty:, off_duty: nil, position: @ood)
    Timesheet.create!(person: @ranger, position:, on_duty:, off_duty:,
                      additional_notes: "test shift")
  end

  def band_at(ago)
    create_timesheet(on_duty: @now - ago)
    MassSignoutReport.execute.rows.first.band
  end

  test "a closed entry is not on the board at all" do
    create_timesheet(on_duty: @now - 2.hours, off_duty: @now - 1.hour)

    assert MassSignoutReport.execute.empty?
  end

  test "the current band runs up to the long threshold" do
    assert_equal :current, band_at(MassSignoutReport::LONG_THRESHOLD - 1.minute)
  end

  test "the long band starts at the threshold" do
    assert_equal :long, band_at(MassSignoutReport::LONG_THRESHOLD)
  end

  test "the long band runs up to the lookback the On Duty board cuts at" do
    assert_equal :long, band_at(OnDutyReport::MAX_SHIFT_LOOKBACK - 1.minute)
  end

  # The two pages partition the open entries between them: anything OnDutyReport
  # drops for being older than its lookback is exactly what this page paints red.
  test "the stale band starts where the On Duty board stops looking" do
    assert_equal :stale, band_at(OnDutyReport::MAX_SHIFT_LOOKBACK)
  end

  test "the longest-open entry sorts first" do
    recent = create_timesheet(on_duty: @now - 1.hour)
    oldest = create_timesheet(on_duty: @now - 3.years)

    assert_equal [oldest.id, recent.id], MassSignoutReport.execute.rows.map { _1.timesheet.id }
  end

  test "counts split the board into what may be swept and what may not" do
    create_timesheet(on_duty: @now - 1.hour)
    create_timesheet(on_duty: @now - 30.hours)
    create_timesheet(on_duty: @now - 3.years)

    result = MassSignoutReport.execute

    assert_equal 3, result.total
    # A superset of stale, not a sibling: the 2028 entry has also been out
    # over a day, and a stat labelled that way has to say so.
    assert_equal 2, result.long_count
    assert_equal 1, result.stale_count
  end

  # There are no position_credit fixtures, so every row prices at 0.0 unless a
  # credit is created -- asserting 0.0 alone would pass with the pricing torn
  # out entirely. The priced row is what makes the orphan's zero mean something.
  test "rows are priced, and an entry whose position is gone prices at zero" do
    PositionCredit.create!(position: @ood, start_time: @now - 2.hours, end_time: @now,
                           credits_per_hour: 2.0, description: "test credits")
    priced = create_timesheet(on_duty: @now - 1.hour)
    orphan = create_timesheet(on_duty: @now - 1.hour)
    orphan.update_column(:position_id, 0)

    rows = MassSignoutReport.execute.rows.index_by { _1.timesheet.id }

    assert_equal 2.0, rows[priced.id].credits
    assert_nil rows[orphan.id].position
    assert_equal 0.0, rows[orphan.id].credits
  end

  # OnDutyReport floors its elapsed at zero for this exact case; the sibling
  # report has to as well or hour_minute_format renders the clock "-2:00".
  test "an on-duty time corrected into the future floors at zero rather than going negative" do
    create_timesheet(on_duty: @now + 2.hours)

    row = MassSignoutReport.execute.rows.first

    assert_equal 0, row.elapsed
    assert_equal :current, row.band
  end

  # The page's write half must re-derive "still open" from the same scope the
  # page was drawn from, or the POST can accept a row the page never offered.
  test "selectable returns only the submitted ids that are still open" do
    open_entry = create_timesheet(on_duty: @now - 1.hour)
    closed = create_timesheet(on_duty: @now - 3.hours, off_duty: @now - 1.hour)

    signable, unsignable = MassSignoutReport.selectable([open_entry.id, closed.id, 987_654_321])

    assert_equal [open_entry.id], signable.map(&:id)
    assert_empty unsignable
  end

  # An entry whose Ranger row is gone comes back in the second bucket: it is
  # still open, but TimesheetLog cannot record a signoff for a missing person.
  test "selectable separates an entry whose Ranger is gone" do
    orphan = create_timesheet(on_duty: @now - 1.hour)
    orphan.update_column(:person_id, 0)

    signable, unsignable = MassSignoutReport.selectable([orphan.id])

    assert_empty signable
    assert_equal [orphan.id], unsignable.map(&:id)
  end
end
