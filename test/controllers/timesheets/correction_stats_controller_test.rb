# frozen_string_literal: true

require "test_helper"

class Timesheets::CorrectionStatsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers

  # Above the 2018 floor and clear of the timesheet fixtures, which occupy
  # 2023-2025. travel_to makes it the current year, so setup_year admits it.
  YEAR = 2031

  setup do
    Rails.cache.clear
    Current.reset

    @now = Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    travel_to @now

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")

    @admin = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    @reviewer = person(:retired_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)

    @position = positions(:ood_position)

    sign_in_as(@admin)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  # --- factories ---------------------------------------------------------

  def as_person(person)
    was = Current.person
    Current.person = person
    yield
  ensure
    Current.person = was
  end

  def create_correction!(owner: @outsider, reviewer: @reviewer,
                         to: Timesheet::STATUS_APPROVED, on_duty: @now)
    entry = as_person(owner) do
      Timesheet.create!(person: owner, position: @position, on_duty:,
                        off_duty: on_duty + 6.hours,
                        review_status: Timesheet::STATUS_APPROVED,
                        additional_notes: "Signed in on the wrong position")
    end

    TimesheetLog.create!(action: TimesheetLog::UPDATE, person_id: owner.id,
                         create_person_id: reviewer&.id, timesheet_id: entry.id,
                         data: { "review_status" => [Timesheet::STATUS_PENDING, to] },
                         year: on_duty.year, created_at: on_duty)
    entry
  end

  def create_missing!(person: @outsider, reviewer: @reviewer, on_duty: @now,
                      review_status: TimesheetMissing::STATUS_APPROVED)
    as_person(person) do
      TimesheetMissing.create!(person_id: person.id, create_person_id: person.id,
                               position_id: @position.id, on_duty:,
                               off_duty: on_duty + 6.hours, partner: "none",
                               review_status:, reviewer_person_id: reviewer&.id,
                               additional_notes: "Never got signed in for this shift")
    end
  end

  # --- authorization -----------------------------------------------------

  # Upstream's TimesheetPolicy::before grants Admin and Timesheet Management
  # every method on the policy, and correctionStatistics() is a hard false that
  # adds no one -- the same gate as the sibling Correction Requests page, and
  # closed to the Event Management reader who may open most /timesheets reports.
  test "admin and timesheet management may view the report" do
    timesheet_manager = person(:auditor_ranger)
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)

    [@admin, timesheet_manager].each do |viewer|
      sign_in_as(viewer)
      get timesheets_correction_stats_path(year: YEAR)
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "event management is turned away from this report" do
    sign_in_as(@event_manager)

    get timesheets_correction_stats_path(year: YEAR)

    assert_redirected_to me_root_path
  end

  test "someone without the role is turned away" do
    sign_in_as(@outsider)

    get timesheets_correction_stats_path(year: YEAR)

    assert_redirected_to me_root_path
  end

  # --- the page ----------------------------------------------------------

  test "a year with no correction activity says so" do
    get timesheets_correction_stats_path(year: YEAR)

    assert_response :success
    assert_select "*", text: /Nothing was decided in #{YEAR}/
  end

  test "the decided counts are drawn for both kinds of request" do
    create_correction!
    create_correction!(to: Timesheet::STATUS_REJECTED)
    create_missing!

    get timesheets_correction_stats_path(year: YEAR)

    assert_response :success
    assert_select "h3", text: "Correction Requests"
    assert_select "h3", text: "Missing-Entry Requests"
    assert_select "*", text: /Approved/
    assert_select "*", text: /Rejected/
  end

  test "the top lists name the position and the ranger who filed the request" do
    create_correction!

    get timesheets_correction_stats_path(year: YEAR)

    assert_response :success
    assert_select "h3", text: "Corrections by Position"
    assert_select "h3", text: "Corrections by Ranger"
    assert_select "th", text: @position.title
    assert_select "th", text: @outsider.callsign
  end

  test "the reviewers table totals each reviewer's decisions" do
    create_correction!
    create_missing!

    get timesheets_correction_stats_path(year: YEAR)

    assert_response :success
    # ui_section titles render as a div, not a heading, so this matches on text.
    assert_select "*", text: /Who Decided Them/
    assert_select "th", text: @reviewer.callsign
    # Both sides land on the one reviewer: one correction and one missing
    # request make two decisions in total.
    assert_select "td", text: "2"
  end

  # The two link targets on this page run on different role lists, and Timesheet
  # Management sits on one side of the split: it may open a ranger's timesheet
  # but not their person page. Both halves are asserted here because gating the
  # leaderboard on the person-page roles -- the obvious-looking choice -- gives
  # this page's largest non-admin audience dead text where a working link
  # belongs, and no assertion on the callsign alone can tell the two apart.
  test "timesheet management gets timesheet links but no person-page links" do
    timesheet_manager = person(:auditor_ranger)
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)
    create_correction!
    create_missing!
    sign_in_as(timesheet_manager)

    get timesheets_correction_stats_path(year: YEAR)

    assert_response :success
    # The leaderboards link to the ranger's timesheet, which this reader may open.
    assert_select "a[href=?]", person_timesheets_path(@outsider)
    # The reviewers table links to the person page, which they may not.
    assert_select "th", text: @reviewer.callsign
    assert_select "a[href=?]", person_path(@reviewer), count: 0
  end

  # An admin may open both, so every callsign on the page is a link.
  test "an admin gets person-page links in the reviewers table" do
    create_correction!

    get timesheets_correction_stats_path(year: YEAR)

    assert_response :success
    assert_select "a[href=?]", person_path(@reviewer)
  end

  # The corrections lists are counted by the year the decision was made, while a
  # person's timesheet page is scoped by the shift's year. Sending the page's
  # year to that link lands the reader on an empty timesheet whenever the two
  # differ, so the corrections links deliberately carry no year.
  test "corrections links carry no year but missing-entry links carry the shift year" do
    create_correction!
    create_missing!

    get timesheets_correction_stats_path(year: YEAR)

    assert_response :success
    assert_select "a[href=?]", person_timesheets_path(@outsider)
    assert_select "a[href=?]", person_timesheets_path(@outsider, year: YEAR)
  end

  # The year the page is asked for is the year it answers with.
  test "the year selector and the report follow the requested year" do
    create_correction!(on_duty: @now - 1.year)

    get timesheets_correction_stats_path(year: YEAR - 1)

    assert_response :success
    assert_select "h1", text: /#{YEAR - 1} Timesheet Correction Statistics/
    assert_select "th", text: @position.title
  end

  # Below the floor the selector cannot show the year, so the page must not
  # answer for it either.
  test "a year below the floor falls back to a year the selector can show" do
    get timesheets_correction_stats_path(year: 2001)

    assert_response :success
    assert_select "h1", text: /2001/, count: 0
  end
end
