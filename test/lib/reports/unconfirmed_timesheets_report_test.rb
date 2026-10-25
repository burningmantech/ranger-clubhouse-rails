# frozen_string_literal: true

require "test_helper"

# Who lands on the report and what their count says. The membership rule is the
# confirmation flag, not the count, so the zero-count row is the case worth
# pinning: it is a real finding, not an empty one.
class UnconfirmedTimesheetsReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include TimesheetAdminTestHelper # confirm_timesheet_for

  YEAR = 2031

  setup do
    @now = Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    travel_to @now
    Current.reset

    @position = positions(:ood_position)
    @person = person(:active_ranger)
  end

  teardown do
    travel_back
    Current.reset
  end

  def log_hours(who = @person, review_status: Timesheet::STATUS_UNVERIFIED, on_duty: @now)
    Timesheet.create!(person: who, position: @position, on_duty:, review_status:,
                      additional_notes: "test shift")
  end

  def callsigns(rows) = rows.map { |row| row.person.callsign }

  test "an unverified entry puts the ranger on the report with a count" do
    log_hours
    log_hours

    row = UnconfirmedTimesheetsReport.execute(year: YEAR).sole

    assert_equal @person.id, row.person.id
    assert_equal 2, row.unverified_count
    assert_predicate row, :needs_verifying?
  end

  test "a rejected entry counts as still open" do
    log_hours(review_status: Timesheet::STATUS_REJECTED)

    assert_equal 1, UnconfirmedTimesheetsReport.execute(year: YEAR).sole.unverified_count
  end

  test "approved and pending entries are settled and do not count" do
    log_hours(review_status: Timesheet::STATUS_APPROVED)
    log_hours(review_status: Timesheet::STATUS_PENDING)

    assert_equal 0, UnconfirmedTimesheetsReport.execute(year: YEAR).sole.unverified_count
  end

  test "everything verified but never confirmed stays on the report at zero" do
    log_hours(review_status: Timesheet::STATUS_VERIFIED)

    row = UnconfirmedTimesheetsReport.execute(year: YEAR).sole

    assert_equal 0, row.unverified_count
    assert_not_predicate row, :needs_verifying?
  end

  test "a confirmed ranger is off the report even with entries still open" do
    log_hours
    confirm_timesheet_for(@person, YEAR)

    assert_empty UnconfirmedTimesheetsReport.execute(year: YEAR)
  end

  # The ordinary production shape: the /me timesheet page creates a person_event
  # row for nearly everyone, so most of the report has a row sitting at false.
  test "a person_event row that says false is still unconfirmed" do
    log_hours
    event = PersonEvent.first_or_new_for_person_year(@person.id, YEAR)
    event.timesheet_confirmed = false
    event.save!(validate: false)

    assert_equal [@person.callsign], callsigns(UnconfirmedTimesheetsReport.execute(year: YEAR))
  end

  test "confirming a different year does not clear this one" do
    log_hours
    confirm_timesheet_for(@person, YEAR - 1)

    assert_equal [@person.callsign], callsigns(UnconfirmedTimesheetsReport.execute(year: YEAR))
  end

  test "hours logged in another year are not this year's problem" do
    log_hours(on_duty: Time.zone.local(YEAR - 1, 8, 26, 12, 0, 0))

    assert_empty UnconfirmedTimesheetsReport.execute(year: YEAR)
  end

  test "only active statuses are chased" do
    log_hours(person(:echelon_ranger))
    log_hours(person(:auditor_ranger))
    log_hours(person(:retired_ranger))

    assert_equal [person(:retired_ranger).callsign],
                 callsigns(UnconfirmedTimesheetsReport.execute(year: YEAR))
  end

  # Ordering is the database's, under a case-insensitive collation. A lowercase
  # callsign is the discriminating case: Ruby's own sort would drop "aardvark"
  # below every capitalised callsign, and real ones like "kungfu booty" exist.
  test "rows read in callsign order, ignoring case" do
    person(:inactive_ranger).update_columns(callsign: "aardvark")
    log_hours(person(:inactive_ranger))
    log_hours(person(:retired_ranger))
    log_hours(@person)

    assert_equal ["aardvark", person(:retired_ranger).callsign, @person.callsign],
                 callsigns(UnconfirmedTimesheetsReport.execute(year: YEAR))
  end
end
