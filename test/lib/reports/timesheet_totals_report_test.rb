# frozen_string_literal: true

require "test_helper"

class TimesheetTotalsReportTest < ActiveSupport::TestCase
  # A year the timesheet fixtures leave alone -- they carry 2023, 2024, 2025.
  YEAR = 2022

  setup do
    Rails.cache.clear
    Current.reset

    @position = positions(:ood_position)
    @position.update!(count_hours: true)
    @person = person(:active_ranger)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def create_credit(rate, year: YEAR, position: @position)
    PositionCredit.create!(position:, start_year: year, end_year: year,
                           start_time: Time.zone.local(year, 8, 20, 0, 0, 0),
                           end_time: Time.zone.local(year, 9, 10, 0, 0, 0),
                           description: "Event week", credits_per_hour: rate)
  end

  def create_timesheet(on_duty:, hours: 3, position: @position, person: @person)
    Timesheet.create!(person:, position:, on_duty:, off_duty: on_duty + hours.hours,
                      additional_notes: "test shift")
  end

  # --- The count_hours filter ----------------------------------------------

  test "a position that does not count hours is left out entirely" do
    @position.update!(count_hours: false)
    create_timesheet(on_duty: Time.zone.local(YEAR, 8, 25, 10, 0, 0))

    roster = TimesheetTotalsReport.summary(year: YEAR)

    assert_empty roster.select { |row| row.person_id == @person.id }
  end

  test "a person with hours in both kinds of position is totaled only for the ones that count" do
    counted = @position
    uncounted = positions(:khaki_supervisor)
    uncounted.update!(count_hours: false)

    create_timesheet(on_duty: Time.zone.local(YEAR, 8, 25, 10, 0, 0), hours: 3, position: counted)
    create_timesheet(on_duty: Time.zone.local(YEAR, 8, 26, 10, 0, 0), hours: 5, position: uncounted)

    row = TimesheetTotalsReport.summary(year: YEAR).find { |r| r.person_id == @person.id }

    assert_equal 1, row.positions.size
    assert_equal 3.hours, row.total_duration
  end

  # --- Credits ---------------------------------------------------------------

  test "credits are computed from the position credit table, cold cache" do
    create_credit(2.0)
    timesheet = create_timesheet(on_duty: Time.zone.local(YEAR, 8, 25, 10, 0, 0), hours: 3)

    row = TimesheetTotalsReport.summary(year: YEAR).find { |r| r.person_id == @person.id }

    assert_in_delta 6.0, row.total_credits, 0.001
    assert_equal timesheet.credits, row.total_credits,
                 "the report and Timesheet#credits must agree"
  end

  # --- Grouping and totals -----------------------------------------------

  test "positions are summed and sorted by title within a person" do
    zebra = Position.create!(title: "Zebra Position", count_hours: true, active: true)
    create_timesheet(on_duty: Time.zone.local(YEAR, 8, 25, 10, 0, 0), hours: 2, position: zebra)
    create_timesheet(on_duty: Time.zone.local(YEAR, 8, 26, 10, 0, 0), hours: 3, position: @position)

    row = TimesheetTotalsReport.summary(year: YEAR).find { |r| r.person_id == @person.id }

    assert_equal [@position.title, "Zebra Position"], row.positions.map(&:title)
    assert_equal 5.hours, row.total_duration
  end

  # Nothing enforces a unique title, so two different positions can share one
  # -- the position_id tiebreaker keeps their order stable across requests
  # instead of riding on an unordered query's row order.
  test "same-titled positions still sort in a stable, deterministic order" do
    twin = Position.create!(title: @position.title, count_hours: true, active: true)
    create_timesheet(on_duty: Time.zone.local(YEAR, 8, 25, 10, 0, 0), hours: 2, position: twin)
    create_timesheet(on_duty: Time.zone.local(YEAR, 8, 26, 10, 0, 0), hours: 3, position: @position)

    row = TimesheetTotalsReport.summary(year: YEAR).find { |r| r.person_id == @person.id }

    assert_equal [@position.id, twin.id].sort, row.positions.map(&:position_id)
  end

  test "the person view totals only that person's positions" do
    other = person(:auditor_ranger)
    create_timesheet(on_duty: Time.zone.local(YEAR, 8, 25, 10, 0, 0), hours: 2, person: @person)
    create_timesheet(on_duty: Time.zone.local(YEAR, 8, 26, 10, 0, 0), hours: 9, person: other)

    detail = TimesheetTotalsReport.person(year: YEAR, person_id: @person.id)

    assert_equal 1, detail.positions.size
    assert_equal 2.hours, detail.total_duration
  end

  test "a person with no qualifying entries gets an empty detail rather than raising" do
    detail = TimesheetTotalsReport.person(year: YEAR, person_id: @person.id)

    assert_empty detail.positions
    assert_equal 0, detail.total_duration
  end

  # --- Ordering ---------------------------------------------------------

  # Upstream sorts with SORT_NATURAL | SORT_FLAG_CASE: digit runs compare as
  # numbers, and they sort ahead of letters.
  test "the roster sorts callsigns naturally" do
    people = [person(:active_ranger), person(:auditor_ranger), person(:retired_ranger),
              person(:inactive_ranger), person(:prospective_ranger)]
    ["10Step", "2Step", "5th Element", "abacus", "Abderian"].each_with_index do |callsign, index|
      people[index].update_columns(callsign:)
      create_timesheet(on_duty: Time.zone.local(YEAR, 8, 25, 10, 0, 0), person: people[index])
    end

    roster = TimesheetTotalsReport.summary(year: YEAR)
    ordered = roster.select { |row| people.map(&:id).include?(row.person_id) }.map(&:callsign)

    assert_equal ["2Step", "5th Element", "10Step", "abacus", "Abderian"], ordered
  end

  test "a person whose row is gone still sorts and reads as deleted" do
    timesheet = create_timesheet(on_duty: Time.zone.local(YEAR, 8, 25, 10, 0, 0))
    timesheet.update_columns(person_id: 0)

    row = TimesheetTotalsReport.summary(year: YEAR).find { |r| r.person_id.zero? }

    assert_equal "Person #0", row.callsign
    assert_equal "deleted", row.person_status
  end

  # A position row can also be gone -- the row is simply excluded, matching
  # upstream's whereIn over a plucked, currently-existing id list.
  test "a timesheet whose position row is gone is left out entirely" do
    timesheet = create_timesheet(on_duty: Time.zone.local(YEAR, 8, 25, 10, 0, 0))
    timesheet.update_columns(position_id: 0)

    roster = TimesheetTotalsReport.summary(year: YEAR)

    assert_empty roster.select { |row| row.person_id == @person.id }
  end
end
