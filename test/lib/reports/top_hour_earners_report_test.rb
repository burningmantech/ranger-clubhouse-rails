# frozen_string_literal: true

require "test_helper"

# The ranking rules, the span arithmetic, and the two ways a shift can be left
# out. Anything the page itself decides is covered by the controller test.
class TopHourEarnersReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  # Clear of the timesheet fixtures, which occupy 2023-2025, so nothing but the
  # shifts a test makes for itself can land in a span.
  YEAR = 2031

  setup do
    Rails.cache.clear
    Current.reset

    @now = Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    travel_to @now

    @position = positions(:ood_position)
    @uncounted = positions(:council_manager)
    @uncounted.update_columns(count_hours: false)

    @ranger = person(:active_ranger)          # TestRanger, active
    @other = person(:ranger_with_custom_gender) # CustomGender, active
    @inactive = person(:inactive_ranger)
    @retired = person(:retired_ranger)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  # --- factories ---------------------------------------------------------

  # Each shift gets its own day so a person can hold several in one year
  # without them overlapping.
  def shift(person:, year:, hours: nil, day: 25, position: @position)
    on_duty = Time.zone.local(year, 8, day, 8, 0, 0)
    Timesheet.create!(person:, position:, on_duty:,
                      off_duty: (on_duty + hours.hours if hours),
                      additional_notes: "test shift")
  end

  def run_report(start_year: YEAR - 4, end_year: YEAR, limit: 250)
    TopHourEarnersReport.execute(start_year:, end_year:, limit:)
  end

  def row_for(report, person) = report.rows.find { |row| row.person.id == person.id }

  def hours(seconds) = (seconds / 3600.0).round(2)

  # --- the ranking -------------------------------------------------------

  test "the biggest single year decides the ranking, not the span total" do
    shift(person: @ranger, year: YEAR - 1, hours: 100)
    shift(person: @other, year: YEAR - 4, hours: 60)
    shift(person: @other, year: YEAR - 3, hours: 60)
    shift(person: @other, year: YEAR - 2, hours: 60)

    report = run_report

    assert_equal [@ranger.id, @other.id], report.rows.map { |row| row.person.id }
    # The runner-up has the larger span total, which is the whole point.
    assert_operator row_for(report, @other).total_duration, :>,
                    row_for(report, @ranger).total_duration
  end

  test "a tie on hours is broken by callsign" do
    shift(person: @ranger, year: YEAR - 1, hours: 40)   # TestRanger
    shift(person: @other, year: YEAR - 1, hours: 40)    # CustomGender

    callsigns = run_report.rows.map(&:callsign)

    assert_equal %w[CustomGender TestRanger], callsigns
  end

  # Built directly, with the later year first, so the assertion turns on the
  # tie-break rather than on the order the database happened to return.
  test "a tie on hours within one ranger's span keeps the earlier year" do
    row = TopHourEarnersReport.build_row(@ranger, { YEAR - 1 => 72_000, YEAR - 3 => 72_000 })

    assert_equal YEAR - 3, row.top_year
  end

  # ASCII puts every capital ahead of every lowercase letter, so without the
  # downcase these two come back the other way round.
  test "the callsign tie-break ignores case" do
    @ranger.update_columns(callsign: "apple")
    @other.update_columns(callsign: "Zebra")
    shift(person: @ranger, year: YEAR - 1, hours: 40)
    shift(person: @other, year: YEAR - 1, hours: 40)

    assert_equal %w[apple Zebra], run_report.rows.map(&:callsign)
  end

  # total is what the page counts to say how many rangers the limit left off, so
  # it has to be the length before the cut, not after it.
  test "the total counts everyone who earned a place" do
    shift(person: @ranger, year: YEAR - 1, hours: 40)
    shift(person: @other, year: YEAR - 1, hours: 30)

    report = run_report

    assert_equal 2, report.total
    assert_equal 2, report.rows.size
    assert_not report.truncated?
  end

  # --- who is counted ----------------------------------------------------

  test "hours on a position that does not earn them are left out" do
    shift(person: @ranger, year: YEAR - 1, hours: 40, position: @uncounted)

    assert_nil row_for(run_report, @ranger)
  end

  test "a ranger with no hours in the span is not listed" do
    shift(person: @ranger, year: YEAR - 1, hours: 40)

    assert_nil row_for(run_report, @other)
    assert_equal 1, run_report.rows.size
  end

  test "an inactive ranger is ranked and a retired one is not" do
    shift(person: @inactive, year: YEAR - 1, hours: 40)
    shift(person: @retired, year: YEAR - 1, hours: 80)

    report = run_report

    assert_equal [@inactive.id], report.rows.map { |row| row.person.id }
    assert_equal Person::INACTIVE, row_for(report, @inactive).status
  end

  test "a shift outside the span is left out" do
    shift(person: @ranger, year: YEAR - 1, hours: 40)
    shift(person: @ranger, year: YEAR - 6, hours: 500)

    report = run_report

    assert_equal 40, hours(row_for(report, @ranger).total_duration)
    assert_equal YEAR - 1, row_for(report, @ranger).top_year
  end

  # --- shifts no one signed out of ---------------------------------------

  # Counting one means valuing it up to this moment, so a sign-in left open
  # since January would be credited with thousands of hours and hold first place
  # for the rest of the year.
  test "a shift no one signed out of counts for nothing" do
    # Opened months ago, still running.
    Timesheet.create!(person: @ranger, position: @position,
                      on_duty: @now - 200.days, off_duty: nil,
                      additional_notes: "test shift")
    shift(person: @ranger, year: YEAR - 1, hours: 10)

    report = run_report

    assert_equal 0.0, hours(row_for(report, @ranger).duration_for(YEAR))
    assert_equal YEAR - 1, row_for(report, @ranger).top_year
    assert_equal 10.0, hours(row_for(report, @ranger).total_duration)
  end

  test "a shift left open in a past year counts for nothing" do
    shift(person: @ranger, year: YEAR - 2, hours: nil)
    shift(person: @ranger, year: YEAR - 1, hours: 10)

    report = run_report

    assert_equal 0.0, hours(row_for(report, @ranger).duration_for(YEAR - 2))
    assert_equal 10.0, hours(row_for(report, @ranger).total_duration)
  end

  # --- rows the database should not be trusted about ---------------------

  # Signed, this row would subtract from a real year: enough to move a ranger's
  # best year, or to take their total to nothing and drop them off the page.
  # The model refuses to make one now, but older rows exist.
  test "a shift that ends before it starts counts for nothing, not against" do
    shift(person: @ranger, year: YEAR - 1, hours: 100)
    backwards = shift(person: @ranger, year: YEAR - 2, hours: 1)
    backwards.update_columns(on_duty: Time.zone.local(YEAR - 2, 8, 25, 18, 0, 0),
                             off_duty: Time.zone.local(YEAR - 2, 8, 20, 18, 0, 0))

    report = run_report
    row = row_for(report, @ranger)

    assert_not_nil row, "a ranger with real hours must survive a backwards row"
    assert_equal 0.0, hours(row.duration_for(YEAR - 2))
    assert_equal 100.0, hours(row.total_duration)
    assert_equal YEAR - 1, row.top_year
  end

  test "a ranger whose only shifts are zero length is not listed" do
    shift(person: @ranger, year: YEAR - 1, hours: 0)

    assert_nil row_for(run_report, @ranger)
  end

  # --- the span ----------------------------------------------------------

  test "every year of the span has a value, rangered or not" do
    shift(person: @ranger, year: YEAR - 1, hours: 12)

    report = run_report
    row = row_for(report, @ranger)

    assert_equal [YEAR - 4, YEAR - 3, YEAR - 2, YEAR - 1, YEAR], report.years
    assert_equal [0.0, 0.0, 0.0, 12.0, 0.0], report.years.map { |y| hours(row.duration_for(y)) }
  end

  test "the eventless years are spanned but draw no column" do
    report = run_report(start_year: 2019, end_year: 2022)

    assert_equal [2019, 2022], report.years
    assert_equal 2019, report.start_year
    assert_equal 2022, report.end_year
  end

  # The ranking is decided on the years the page draws. Counting a year it does
  # not draw would seat a ranger at the top on a figure no column explains.
  test "hours in an eventless year count for nothing" do
    shift(person: @ranger, year: 2020, hours: 9)
    shift(person: @other, year: 2022, hours: 4)

    report = run_report(start_year: 2019, end_year: 2022)

    assert_nil row_for(report, @ranger)
    assert_equal [@other.id], report.rows.map { |row| row.person.id }
  end

  test "a ranking decided on a drawn year always has a cell to mark" do
    shift(person: @ranger, year: 2020, hours: 99)
    shift(person: @ranger, year: 2022, hours: 4)

    row = row_for(run_report(start_year: 2019, end_year: 2022), @ranger)

    assert_equal 2022, row.top_year
    assert_equal 4.0, hours(row.top_duration)
    assert row.top_year?(2022)
  end

  # --- what the query string is allowed to say ---------------------------

  test "a span given backwards is turned around" do
    report = run_report(start_year: YEAR, end_year: YEAR - 3)

    assert_equal YEAR - 3, report.start_year
    assert_equal YEAR, report.end_year
  end

  # Junk of every shape a query string can produce: an array, a nested hash, a
  # word, and nothing at all.
  test "a parameter the report cannot read falls back to the default span" do
    [[["nonsense"], { "a" => "b" }], ["banana", ""]].each do |start, finish|
      report = TopHourEarnersReport.execute(start_year: start, end_year: finish,
                                            limit: "banana")

      assert_equal YEAR - TopHourEarnersReport::DEFAULT_SPAN, report.start_year,
                   "start_year #{start.inspect} should fall back"
      assert_equal YEAR, report.end_year, "end_year #{finish.inspect} should fall back"
      assert_equal TopHourEarnersReport::DEFAULT_LIMIT, report.limit
    end
  end

  test "an eventless year moves to the closest year on offer" do
    report = TopHourEarnersReport.execute(start_year: 2020, end_year: 2021)

    assert_equal 2019, report.start_year
    assert_equal 2022, report.end_year
  end

  # Sent to the default instead, 2009 to 2015 would run from 2015 to this year:
  # a different span from the one asked for.
  test "a year outside the ones on offer becomes the nearer end" do
    report = run_report(start_year: 2009, end_year: 2015)

    assert_equal 2010, report.start_year
    assert_equal 2015, report.end_year

    report = run_report(start_year: 1907, end_year: YEAR + 50)

    assert_equal 2010, report.start_year
    assert_equal YEAR, report.end_year
  end

  test "a limit outside the ones on offer falls back to the default" do
    assert_equal TopHourEarnersReport::DEFAULT_LIMIT, run_report(limit: 9_999).limit
    assert_equal 50, run_report(limit: "50").limit
  end

  # The export is built by the controller, so its columns are asserted there.
end
