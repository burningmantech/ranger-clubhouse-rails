# frozen_string_literal: true

require "test_helper"

class HoursCreditsReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include CacheTestHelper

  # Clear of the timesheet fixtures, which occupy 2023-2025.
  YEAR = 2031

  # A whole day either side of the event week, so a shift can be placed well
  # inside a part of the season or made to straddle a boundary on purpose.
  EVENT_START = Time.zone.local(YEAR, 8, 24, 0, 0, 0)
  EVENT_END = Time.zone.local(YEAR, 9, 1, 0, 0, 0)

  setup do
    Rails.cache.clear
    Current.reset
    travel_to Time.zone.local(YEAR, 9, 10, 12, 0, 0)

    @person = person(:active_ranger)
    @position = positions(:ood_position)
    @event_dates = create_event_dates
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  # The report reads the event week; the other dates are here only because the
  # record insists on them.
  def create_event_dates
    EventDate.create!(event_start: EVENT_START, event_end: EVENT_END,
                      pre_event_start: EVENT_START - 3.weeks,
                      pre_event_slot_start: EVENT_START - 3.weeks,
                      pre_event_slot_end: EVENT_START,
                      post_event_end: EVENT_END + 2.weeks)
  end

  def shift(person: @person, position: @position, on_duty:, off_duty:)
    Timesheet.create!(person:, position:, on_duty:, off_duty:,
                      additional_notes: "test shift")
  end

  def row_for(person = @person, year: YEAR)
    HoursCreditsReport.execute(year:).rows.find { |row| row.person_id == person.id }
  end

  # --- who is listed ------------------------------------------------------

  # Both halves of the same rule: the ranger who turned in a shift is listed
  # with its hours, and no one else is listed at all.
  test "only the rangers who turned in hours are listed" do
    shift(on_duty: EVENT_START + 1.hour, off_duty: EVENT_START + 5.hours)

    report = HoursCreditsReport.execute(year: YEAR)

    assert_equal [@person.id], report.rows.map(&:person_id)
    assert_equal 4.hours.to_i, report.rows.first.event_duration
  end

  # Hours turned in under one of these statuses are not the season's story, and
  # the page says as much.
  test "the statuses the report does not cover are left out" do
    [:alpha_ranger, :auditor_ranger, :bonked_ranger,
     :prospective_ranger, :past_prospective_ranger].each do |fixture|
      shift(person: person(fixture),
            on_duty: EVENT_START + 1.hour, off_duty: EVENT_START + 5.hours)
    end

    assert_empty HoursCreditsReport.execute(year: YEAR).rows
  end

  test "hours from another year do not put a ranger on the page" do
    shift(on_duty: EVENT_START - 1.year, off_duty: EVENT_START - 1.year + 4.hours)

    assert_empty HoursCreditsReport.execute(year: YEAR).rows
  end

  # --- where the hours land ----------------------------------------------

  test "a shift wholly before the event counts as pre-event" do
    shift(on_duty: EVENT_START - 10.hours, off_duty: EVENT_START - 6.hours)

    row = row_for

    assert_equal 4.hours.to_i, row.pre_event_duration
    assert_equal 0, row.event_duration
    assert_equal 0, row.post_event_duration
  end

  test "a shift wholly after the event counts as post-event" do
    shift(on_duty: EVENT_END + 6.hours, off_duty: EVENT_END + 10.hours)

    row = row_for

    assert_equal 4.hours.to_i, row.post_event_duration
    assert_equal 0, row.pre_event_duration
    assert_equal 0, row.event_duration
  end

  # The boundary splits the shift rather than sending all of it to whichever
  # part it started in -- otherwise a ranger who signs in an hour before the
  # gates open has their whole event week counted as build-up.
  test "a shift crossing the start of the event is split at the boundary" do
    shift(on_duty: EVENT_START - 2.hours, off_duty: EVENT_START + 3.hours)

    row = row_for

    assert_equal 2.hours.to_i, row.pre_event_duration
    assert_equal 3.hours.to_i, row.event_duration
    assert_equal 0, row.post_event_duration
  end

  test "a shift crossing the end of the event is split at the boundary" do
    shift(on_duty: EVENT_END - 3.hours, off_duty: EVENT_END + 2.hours)

    row = row_for

    assert_equal 3.hours.to_i, row.event_duration
    assert_equal 2.hours.to_i, row.post_event_duration
    assert_equal 0, row.pre_event_duration
  end

  test "a shift running the whole event is split into all three parts" do
    shift(on_duty: EVENT_START - 4.hours, off_duty: EVENT_END + 5.hours)

    row = row_for

    assert_equal 4.hours.to_i, row.pre_event_duration
    assert_equal (EVENT_END - EVENT_START).to_i, row.event_duration
    assert_equal 5.hours.to_i, row.post_event_duration
  end

  # The first moment of the event week is event time, not build-up.
  test "a shift starting exactly at the start of the event is event time" do
    shift(on_duty: EVENT_START, off_duty: EVENT_START + 2.hours)

    row = row_for

    assert_equal 2.hours.to_i, row.event_duration
    assert_equal 0, row.pre_event_duration
  end

  # The last moment is the other way about: a shift signing on exactly as the
  # event week closes has no time left inside it, so all of it is the strike.
  test "a shift starting exactly at the end of the event is post-event" do
    shift(on_duty: EVENT_END, off_duty: EVENT_END + 2.hours)

    row = row_for

    assert_equal 2.hours.to_i, row.post_event_duration
    assert_equal 0, row.event_duration
  end

  # --- what the totals mean ----------------------------------------------

  test "the total is the three parts added up" do
    shift(on_duty: EVENT_START - 2.hours, off_duty: EVENT_START + 3.hours)
    shift(on_duty: EVENT_END + 1.hour, off_duty: EVENT_END + 2.hours)

    row = row_for

    assert_equal 6.hours.to_i, row.counted_duration
  end

  # A position that earns no hours still earns credits, and the credits are
  # placed in the part of the season they were earned in. The hours themselves
  # are left out of every column the page draws.
  test "a position that earns no hours still earns credits" do
    no_hours = positions(:non_eligible_position)
    no_hours.update!(count_hours: false)
    PositionCredit.create!(position: no_hours, credits_per_hour: 2.0,
                           description: "test credits",
                           start_time: EVENT_START, end_time: EVENT_END)

    shift(position: no_hours, on_duty: EVENT_START + 1.hour, off_duty: EVENT_START + 3.hours)

    row = row_for

    assert_equal 0, row.counted_duration, "hours should be left out"
    assert_in_delta 4.0, row.event_credits, 0.001, "credits should still be earned"
  end

  test "credits land in the same part of the season as the hours" do
    PositionCredit.create!(position: @position, credits_per_hour: 1.0,
                           description: "test credits",
                           start_time: EVENT_START - 1.day, end_time: EVENT_END)

    shift(on_duty: EVENT_START - 2.hours, off_duty: EVENT_START + 3.hours)

    row = row_for

    assert_in_delta 2.0, row.pre_event_credits, 0.001
    assert_in_delta 3.0, row.event_credits, 0.001
    # The total is the parts added up, so a split shift is where it can be seen
    # to be more than any one of them.
    assert_in_delta 5.0, row.total_credits, 0.001
  end

  # The year's credit cache is filled a position at a time by whichever pages
  # ran first, so an entry that is there is not the whole year. Read as if it
  # were, the positions it had not seen yet earned nothing, and the total
  # depended on what had been browsed before.
  test "credits do not depend on what the credit cache already holds" do
    [@position, positions(:mentor_lead)].each do |position|
      PositionCredit.create!(position:, credits_per_hour: 1.0, description: "test credits",
                             start_time: EVENT_START, end_time: EVENT_END)
      shift(position:, on_duty: EVENT_START + 1.hour, off_duty: EVENT_START + 3.hours)
    end

    with_cache_store do
      PositionCredit.find_for_year_position(YEAR, @position.id)

      # Two hours at a credit an hour on each position: what a cold cache gives.
      assert_in_delta 4.0, HoursCreditsReport.execute(year: YEAR).total_credits, 0.001
    end
  end

  # A shift no one signed out of is valued up to this moment, the same way a
  # ranger's own timesheet page values it.
  test "a shift still signed in is counted up to now" do
    shift(on_duty: EVENT_END + 2.hours, off_duty: nil)

    assert_equal (Current.time - (EVENT_END + 2.hours)).to_i, row_for.post_event_duration
  end

  # --- the rest of the row ------------------------------------------------

  test "years counts the years the ranger has rangered" do
    shift(on_duty: EVENT_START + 1.hour, off_duty: EVENT_START + 5.hours)

    # The fixture carries two years of service.
    assert_equal 2, row_for.years
  end

  test "a ranger goes by their preferred name" do
    preferred = person(:ranger_with_custom_gender)
    shift(person: preferred, on_duty: EVENT_START + 1.hour, off_duty: EVENT_START + 5.hours)

    assert_equal "#{preferred.desired_first_name} #{preferred.last_name}",
                 row_for(preferred).name
  end

  # Spelled out rather than compared against its own sort: an empty roster and a
  # roster of one both satisfy "already in order" while proving nothing.
  test "the roster is ordered by callsign" do
    rangers = [@person, person(:inactive_ranger), person(:retired_ranger)]
    rangers.each do |ranger|
      shift(person: ranger, on_duty: EVENT_START + 1.hour, off_duty: EVENT_START + 5.hours)
    end

    callsigns = HoursCreditsReport.execute(year: YEAR).rows.map(&:callsign)

    assert_equal rangers.map(&:callsign).sort_by(&:downcase), callsigns
  end

  test "the report totals every row it lists" do
    shift(on_duty: EVENT_START + 1.hour, off_duty: EVENT_START + 5.hours)
    shift(person: person(:inactive_ranger),
          on_duty: EVENT_START + 1.hour, off_duty: EVENT_START + 3.hours)

    assert_equal 6.hours.to_i, HoursCreditsReport.execute(year: YEAR).total_duration
  end

  # --- a year with no event ----------------------------------------------

  # Without the two boundaries there is nothing to split a season at, so the
  # report refuses to run rather than guessing.
  test "a year with no event dates produces no rows" do
    @event_dates.destroy!
    shift(on_duty: EVENT_START + 1.hour, off_duty: EVENT_START + 5.hours)

    report = HoursCreditsReport.execute(year: YEAR)

    assert_not report.event_dates?
    assert_empty report.rows
  end

  test "a year with event dates says so" do
    assert_predicate HoursCreditsReport.execute(year: YEAR), :event_dates?
  end

  # Half-entered or back-to-front dates would otherwise be counted from, putting
  # tens of thousands of hours in one column and taking them out of another.
  test "a year whose event has no end date cannot run the report" do
    @event_dates.update_columns(event_end: nil)
    shift(on_duty: EVENT_START + 1.hour, off_duty: EVENT_START + 5.hours)

    report = HoursCreditsReport.execute(year: YEAR)

    assert_not report.event_dates?
    assert_empty report.rows
  end

  test "a year whose event ends before it starts cannot run the report" do
    @event_dates.update_columns(event_end: EVENT_START - 1.day)
    shift(on_duty: EVENT_START + 1.hour, off_duty: EVENT_START + 5.hours)

    assert_not HoursCreditsReport.execute(year: YEAR).event_dates?
  end

  # --- shifts the data got wrong ------------------------------------------

  # A sign-out earlier than its sign-in counts as no time. Left as it is, it
  # cancels out hours the ranger really put in.
  # Written straight to the columns: the model refuses to save one now, which is
  # why only the older rows carry it.
  test "a shift signed out before it was signed in counts as nothing" do
    reversed = shift(on_duty: EVENT_START + 1.hour, off_duty: EVENT_START + 5.hours)
    reversed.update_columns(on_duty: EVENT_START + 5.hours, off_duty: EVENT_START + 1.hour)
    shift(on_duty: EVENT_START + 10.hours, off_duty: EVENT_START + 14.hours)

    row = row_for

    assert_equal 4.hours.to_i, row.counted_duration, "the good shift should stand alone"
    assert_operator row.event_duration, :>=, 0
  end

  test "a ranger whose seasons are not a list of years counts as none" do
    @person.update_columns(years_as_ranger: "{}")
    shift(on_duty: EVENT_START + 1.hour, off_duty: EVENT_START + 5.hours)

    assert_equal 0, row_for.years
  end
end
