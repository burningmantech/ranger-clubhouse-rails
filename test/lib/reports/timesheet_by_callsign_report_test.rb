# frozen_string_literal: true

require "test_helper"

# The parts the controller test cannot reach: the credit arithmetic, which the
# test cache store would otherwise hide, and the two ordering rules.
class TimesheetByCallsignReportTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role

  # A year the timesheet fixtures leave alone -- they carry 2023, 2024, 2025.
  YEAR = 2022

  setup do
    Rails.cache.clear
    Current.reset

    @position = positions(:ood_position)
    @person = person(:active_ranger)

    # ood_position belongs to no team, so only a full-report reader sees it.
    # The scoped path is the controller test's job.
    ensure_role(Role::ADMIN, "Admin")
    @viewer = person(:echelon_ranger)
    grant_role(@viewer, Role::ADMIN)
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

  # --- Credits ------------------------------------------------------------

  # The test store is a null_store and production evicts, so a bulk path that
  # trusted an empty cache read would price every entry at 0.0 -- a silently
  # wrong report rather than a slow one. Asserting a real number here is what
  # makes the credits feature testable at all.
  test "credits are computed from the position credit table, cold cache" do
    create_credit(2.0)
    timesheet = create_timesheet(on_duty: Time.zone.local(YEAR, 8, 25, 10, 0, 0), hours: 3)

    credits = TimesheetByCallsignReport.credits_by_id([timesheet])

    assert_in_delta 6.0, credits[timesheet.id], 0.001
    assert_equal timesheet.credits, credits[timesheet.id],
                 "the report and Timesheet#credits must agree"
  end

  test "the roster totals the credits it computed" do
    create_credit(2.0)
    create_timesheet(on_duty: Time.zone.local(YEAR, 8, 25, 10, 0, 0), hours: 3)
    create_timesheet(on_duty: Time.zone.local(YEAR, 8, 26, 10, 0, 0), hours: 1)

    row = TimesheetByCallsignReport.summary(year: YEAR, viewer: @viewer)
                                   .people.find { |p| p.person_id == @person.id }

    assert_in_delta 8.0, row.total_credits, 0.001
  end

  test "an entry outside every credit window earns nothing" do
    create_credit(2.0)
    timesheet = create_timesheet(on_duty: Time.zone.local(YEAR, 3, 1, 10, 0, 0), hours: 3)

    credits = TimesheetByCallsignReport.credits_by_id([timesheet])

    assert_in_delta 0.0, credits[timesheet.id], 0.001
  end

  # for_year compares the stored wall clock while the value read back is cast
  # into Time.zone, so an entry can sit in one year's scope and belong to the
  # next year's credit table. Pricing by the report year instead of the entry's
  # own would show different credits here than on /person/:id/timesheets.
  test "each entry is priced against its own year, not the report's" do
    create_credit(2.0, year: YEAR)
    create_credit(10.0, year: YEAR + 1)
    this_year = create_timesheet(on_duty: Time.zone.local(YEAR, 8, 25, 10, 0, 0), hours: 3)
    next_year = create_timesheet(on_duty: Time.zone.local(YEAR + 1, 8, 25, 10, 0, 0), hours: 3)

    credits = TimesheetByCallsignReport.credits_by_id([this_year, next_year])

    assert_in_delta 6.0, credits[this_year.id], 0.001
    assert_in_delta 30.0, credits[next_year.id], 0.001
  end

  # The Laravel-shared schema carries no FK, so position can be nil even though
  # the association is not optional.
  test "an entry whose position row is gone earns nothing rather than raising" do
    timesheet = create_timesheet(on_duty: Time.zone.local(YEAR, 8, 25, 10, 0, 0))
    timesheet.update_columns(position_id: 0)

    credits = TimesheetByCallsignReport.credits_by_id([timesheet.reload])

    assert_in_delta 0.0, credits[timesheet.id], 0.001
  end

  # --- Ordering -----------------------------------------------------------

  # Upstream sorts with SORT_NATURAL | SORT_FLAG_CASE: digit runs compare as
  # numbers, and they sort ahead of letters.
  test "the roster sorts callsigns naturally" do
    # Existing fixtures renamed rather than new Person records: the callsign is
    # the only field this test cares about, and person has a long required set.
    people = [person(:active_ranger), person(:auditor_ranger), person(:retired_ranger),
              person(:inactive_ranger), person(:prospective_ranger)]
    ["10Step", "2Step", "5th Element", "abacus", "Abderian"].each_with_index do |callsign, index|
      people[index].update_columns(callsign:)
      create_timesheet(on_duty: Time.zone.local(YEAR, 8, 25, 10, 0, 0), person: people[index])
    end

    roster = TimesheetByCallsignReport.summary(year: YEAR, viewer: @viewer).people
    ordered = roster.select { |row| people.map(&:id).include?(row.person_id) }.map(&:callsign)

    assert_equal ["2Step", "5th Element", "10Step", "abacus", "Abderian"], ordered
  end

  test "a person whose row is gone still sorts and reads as deleted" do
    timesheet = create_timesheet(on_duty: Time.zone.local(YEAR, 8, 25, 10, 0, 0))
    timesheet.update_columns(person_id: 0)

    row = TimesheetByCallsignReport.summary(year: YEAR, viewer: @viewer)
                                   .people.find { |p| p.person_id.zero? }

    assert_equal "Person #0", row.callsign
    assert_equal "deleted", row.person_status
  end
end
