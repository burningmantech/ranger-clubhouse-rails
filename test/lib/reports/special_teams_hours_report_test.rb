# frozen_string_literal: true

require "test_helper"

class SpecialTeamsHoursReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  # Clear of the timesheet fixtures, which occupy 2023-2025.
  YEAR = 2031

  setup do
    Current.reset
    travel_to Time.zone.local(YEAR, 8, 26, 12, 0, 0)

    # Positions of the test's own, so no fixture timesheet, grant or sign-up
    # lands on them and every count below is exact.
    @green = Position.create!(title: "Test Green Dot", active: true, type: Position::TYPE_FRONTLINE)
    @sanctuary = Position.create!(title: "Test Sanctuary", active: true, type: Position::TYPE_FRONTLINE)
    @elsewhere = Position.create!(title: "Test Elsewhere", active: true, type: Position::TYPE_FRONTLINE)

    @ranger = person(:active_ranger)
    @echelon = person(:echelon_ranger)
    @retired = person(:retired_ranger)
  end

  teardown do
    travel_back
    Current.reset
  end

  def shift(person, position, year, hours, month: 8, day: 20, hour: 9)
    on_duty = Time.local(year, month, day, hour)
    Timesheet.create!(person:, position:, on_duty:, off_duty: on_duty + hours.hours,
                      additional_notes: "test shift")
  end

  # A six-hour shift on the given day. The default day has ended by the time the
  # tests travel to, 26 August YEAR at noon, in every year they use.
  def sign_up(person, position, year, day: 20)
    slot = Slot.create!(position:, begins: Time.local(year, 8, day, 9), ends: Time.local(year, 8, day, 15),
                        max: 10, active: true)
    PersonSlot.create!(person:, slot:)
  end

  def build_report(position_ids: [@green.id, @sanctuary.id], start_year: YEAR - 1, end_year: YEAR, **)
    SpecialTeamsHoursReport.execute(position_ids:, start_year:, end_year:, **)
  end

  def row_for(report, person) = report.rows.find { |row| row.person.id == person.id }

  test "adds up each person's hours per year across every chosen position" do
    shift(@ranger, @green, YEAR - 1, 6)
    # A second chosen position in the same year joins the same total rather
    # than replacing it.
    shift(@ranger, @sanctuary, YEAR - 1, 2, day: 21)
    shift(@ranger, @green, YEAR, 4)
    shift(@echelon, @sanctuary, YEAR, 3)
    # Not a chosen position, so neither its hours nor its person appear.
    shift(@retired, @elsewhere, YEAR, 10)

    report = build_report

    assert_equal [YEAR - 1, YEAR], report.years
    # Callsign order, compared without case as the database collation does.
    assert_equal [@echelon, @ranger].sort_by { |person| person.callsign.downcase }.map(&:id),
                 report.rows.map { |row| row.person.id }

    ranger = row_for(report, @ranger)
    assert_equal 8.hours.to_i, ranger.hours_for(YEAR - 1)
    assert_equal 4.hours.to_i, ranger.hours_for(YEAR)
    assert_equal 12.hours.to_i, ranger.total_hours

    echelon = row_for(report, @echelon)
    assert_equal 0, echelon.hours_for(YEAR - 1)
    assert_equal 3.hours.to_i, echelon.hours_for(YEAR)

    assert_equal 7.hours.to_i, report.hours_total(YEAR)
    assert_equal 15.hours.to_i, report.total_hours
  end

  test "a shift still in progress lists the person but adds nothing" do
    Timesheet.create!(person: @retired, position: @green, on_duty: Time.local(YEAR, 8, 26, 9),
                      additional_notes: "test shift")

    row = row_for(build_report, @retired)

    assert row, "someone signed in to a chosen position is listed"
    assert_equal 0, row.total_hours
  end

  test "an entry signed out before it was signed in counts as nothing, not a debit" do
    shift(@ranger, @green, YEAR, 5)
    backwards = shift(@ranger, @green, YEAR, 1, day: 22)
    backwards.update_column(:off_duty, backwards.on_duty - 2.hours)

    assert_equal 5.hours.to_i, row_for(build_report, @ranger).hours_for(YEAR)
  end

  test "a shift late on New Year's Eve counts toward the year it began in" do
    on_duty = Time.local(YEAR - 1, 12, 31, 23, 15)
    Timesheet.create!(person: @ranger, position: @green, on_duty:, off_duty: on_duty + 30.minutes,
                      additional_notes: "test shift")

    report = build_report(start_year: YEAR - 1, end_year: YEAR - 1)

    assert_equal 30.minutes.to_i, row_for(report, @ranger).hours_for(YEAR - 1)
  end

  test "never lists a locked account" do
    deceased = person(:deceased_ranger)
    shift(deceased, @green, YEAR, 4)
    PersonPosition.create!(person: deceased, position: @green)

    report = build_report(include_holders: true, show_signups: true)

    assert_nil row_for(report, deceased)
  end

  test "holders with no hours are listed only when asked for" do
    PersonPosition.create!(person: @retired, position: @green)

    assert_nil row_for(build_report, @retired)

    row = row_for(build_report(include_holders: true), @retired)
    assert row
    assert_equal 0, row.total_hours
  end

  test "sign-ups are counted per year, and list people who only signed up, only when asked for" do
    shift(@ranger, @green, YEAR - 1, 6)
    sign_up(@ranger, @green, YEAR - 1)
    sign_up(@retired, @green, YEAR)
    sign_up(@retired, @sanctuary, YEAR)
    # Neither counts: one is not a chosen position, the other is outside the span.
    sign_up(@retired, @elsewhere, YEAR)
    sign_up(@retired, @green, YEAR - 3)

    report = build_report(show_signups: true)

    assert report.show_signups
    assert_equal 1, row_for(report, @ranger).signups_for(YEAR - 1)
    retired = row_for(report, @retired)
    assert_equal 2, retired.signups_for(YEAR)
    assert_equal 2, retired.total_signups
    assert_equal 0, retired.total_hours
    assert_equal 3, report.total_signups

    without = build_report
    assert_nil row_for(without, @retired)
    assert_equal 0, row_for(without, @ranger).total_signups
  end

  # Set beside hours, which a shift adds only once it is signed out, a sign-up
  # for a shift still to come would read as a no-show.
  test "a sign-up counts only once its shift has ended" do
    sign_up(@retired, @green, YEAR, day: 20)   # ended
    sign_up(@retired, @green, YEAR, day: 26)   # running: 09:00 to 15:00, and it is noon
    sign_up(@retired, @green, YEAR, day: 28)   # still to come

    assert_equal 1, row_for(build_report(show_signups: true), @retired).signups_for(YEAR)
  end

  test "a span over 2020 and 2021 draws neither year and counts nothing recorded in them" do
    shift(@ranger, @green, 2019, 5)
    shift(@ranger, @green, 2020, 7)

    report = build_report(start_year: 2019, end_year: 2022)

    assert_equal [2019, 2022], report.years
    assert report.skips_years?
    assert_equal 5.hours.to_i, row_for(report, @ranger).total_hours
  end
end
