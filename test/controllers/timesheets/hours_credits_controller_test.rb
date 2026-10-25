# frozen_string_literal: true

require "test_helper"

class Timesheets::HoursCreditsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper
  include ReportCardTestHelper
  include ActiveSupport::Testing::TimeHelpers

  # Clear of the timesheet fixtures, which occupy 2023-2025.
  YEAR = 2031

  EVENT_START = Time.zone.local(YEAR, 8, 24, 0, 0, 0)
  EVENT_END = Time.zone.local(YEAR, 9, 1, 0, 0, 0)

  setup do
    Rails.cache.clear
    Current.reset
    travel_to Time.zone.local(YEAR, 9, 10, 12, 0, 0)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")

    @admin = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @outsider = person(:retired_ranger)
    @ranger = person(:ranger_with_custom_gender)
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)

    @position = positions(:ood_position)
    create_event_dates

    sign_in_as(@admin)
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

  def shift(person: @ranger, on_duty: EVENT_START + 1.hour, hours: 4)
    Timesheet.create!(person:, position: @position, on_duty:,
                      off_duty: on_duty + hours.hours, additional_notes: "test shift")
  end

  # --- who may read it ---------------------------------------------------

  # A shift first, so both readers are rendering a ledger rather than the empty
  # state -- an empty page would pass this while never reaching a single row.
  test "admin and timesheet management may view the report" do
    shift
    timesheet_manager = person(:auditor_ranger)
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)

    [@admin, timesheet_manager].each do |viewer|
      sign_in_as(viewer)
      get timesheets_hours_credits_path(year: YEAR)

      assert_response :success, "#{viewer.callsign} should be allowed in"
      assert_match @ranger.callsign, response.body, "#{viewer.callsign} should see the ledger"
    end
  end

  test "event management is turned away from this report" do
    sign_in_as(@event_manager)

    get timesheets_hours_credits_path(year: YEAR)

    assert_redirected_to me_root_path
  end

  test "someone without the role is turned away" do
    sign_in_as(@outsider)

    get timesheets_hours_credits_path(year: YEAR)

    assert_redirected_to me_root_path
  end

  # Timesheet Management is deliberately kept off the person pages, so their
  # copy of the ledger names each ranger without linking them.
  test "a reader who cannot open person pages gets plain callsigns" do
    shift
    timesheet_manager = person(:auditor_ranger)
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)
    sign_in_as(timesheet_manager)

    get timesheets_hours_credits_path(year: YEAR)

    assert_response :success
    assert_select "th.hours-credits-callsign", text: /#{@ranger.callsign}/
    assert_select "a[href=?]", person_path(@ranger), count: 0
  end

  # Reading the ledger does not carry permission to see who people are off the
  # playa. Timesheet Management holds neither capability.
  test "a reader without the capability gets no name or email column" do
    shift
    timesheet_manager = person(:auditor_ranger)
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)
    sign_in_as(timesheet_manager)

    get timesheets_hours_credits_path(year: YEAR)

    assert_response :success
    assert_select "th", text: "Name", count: 0
    assert_select "th", text: "Email", count: 0
    assert_no_match(/#{@ranger.email}/, response.body)
  end

  # --- the page ----------------------------------------------------------

  test "the ledger draws a row of hours and credits" do
    shift

    get timesheets_hours_credits_path(year: YEAR)

    assert_response :success
    assert_select "h1", text: /#{YEAR} Hours & Credits/
    assert_select "td", text: "4.00"
    assert_match "Showing 1 of 1 person", response.body
    # The layout morphs on refresh and reconciles by id, so a repeated one can
    # silently drop a field -- the filter form carries a year of its own beside
    # the selector in the hero.
    assert_unique_dom_ids
  end

  # Each part of the season gets its own pair of columns under a band naming it.
  # A column heading is read on its own, so the pair repeats the band's name for
  # a screen reader -- eight headings all saying "Hours" or "Credits" leave a
  # listener no way to place the numbers under them.
  test "the ledger groups the columns by part of the season" do
    shift

    get timesheets_hours_credits_path(year: YEAR)

    assert_response :success
    ["Totals", "Pre-Event", "Event Week", "Post-Event"].each do |group|
      assert_select "th[scope=colgroup]", text: group
      assert_select "th span.sr-only", text: group, count: 2
    end
  end

  # How the ledger is counted is read with the ledger: the card sits under the
  # stat row, which only a year with rows has.
  test "the card explains how the ledger is counted, event week included" do
    shift

    get timesheets_hours_credits_path(year: YEAR)

    assert_report_card
    assert_select "details dd", text: "The #{YEAR} event week runs Sun Aug 24 to Mon Sep 1."
  end

  test "a year with no timesheets says so" do
    get timesheets_hours_credits_path(year: YEAR)

    assert_response :success
    assert_match "No #{YEAR} timesheets were turned in.", response.body
    assert_report_card count: 0
  end

  # Without the two boundaries there is nothing to split a season at, so the
  # page has to say why it is not drawing a ledger.
  test "a year with no event dates cannot run the report" do
    EventDate.destroy_all
    shift

    get timesheets_hours_credits_path(year: YEAR)

    assert_response :success
    assert_match "The #{YEAR} Event Dates Have Not Been Set", response.body
    assert_select "table", count: 0
    assert_report_card count: 0
  end

  # --- the filters -------------------------------------------------------

  test "the status filter narrows the ledger" do
    shift(person: @ranger)
    shift(person: person(:inactive_ranger))

    get timesheets_hours_credits_path(year: YEAR, status: "inactive")

    assert_response :success
    assert_match person(:inactive_ranger).callsign, response.body
    assert_select "th.hours-credits-callsign", text: /#{@ranger.callsign}/, count: 0
    assert_match "Showing 1 of 2 people", response.body
  end

  test "the years filter narrows the ledger" do
    # The fixtures carry two years of service for one and none for the other.
    shift(person: @admin)
    shift(person: @ranger)

    get timesheets_hours_credits_path(year: YEAR, years: "2")

    assert_response :success
    assert_select "th.hours-credits-callsign", text: /#{@admin.callsign}/
    assert_select "th.hours-credits-callsign", text: /#{@ranger.callsign}/, count: 0
  end

  # Each filter on its own has takers here -- one active ranger and one with two
  # years -- but no one is both, and the page has to say that rather than read
  # as a year in which no one rangered.
  test "filters that match no one say so rather than reading as an empty year" do
    shift(person: @ranger)                     # active, no years of service
    shift(person: person(:inactive_ranger))    # inactive, two years of service

    get timesheets_hours_credits_path(year: YEAR, status: "active", years: "2")

    assert_response :success
    assert_match "No ranger matches these filters.", response.body
  end

  # A value no ranger on the page carries would otherwise narrow the ledger to
  # nothing while drawing a chip claiming it had narrowed it to something.
  test "a filter the roster does not hold is ignored" do
    shift

    get timesheets_hours_credits_path(year: YEAR, status: "nonsense", years: ["x"])

    assert_response :success
    assert_match "Showing 1 of 1 person", response.body
  end

  # A year-scoped page whose filter form dropped the year would bounce the
  # reader back to the current year on every Apply.
  test "the filter form carries the year" do
    shift

    get timesheets_hours_credits_path(year: YEAR)

    assert_response :success
    assert_select "input[type=hidden][name=year][value=?]", YEAR.to_s
  end

  # --- the export --------------------------------------------------------

  test "the export carries the whole ledger" do
    shift(person: @ranger, hours: 4)

    get timesheets_hours_credits_path(year: YEAR, format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match "#{YEAR}-hours-credits.csv", response.headers["Content-Disposition"]

    lines = response.body.split("\n")

    assert_equal "Callsign,Email,Full Name,Status,#{YEAR} Total Hours," \
                 "#{YEAR} Total Credits,Pre-Event Hours,Pre-Event Credits," \
                 "Event Hours,Event Credits,Post-Event Hours,Post-Event Credits,Years",
                 lines.first
    # "Cus Gender", not "Custom Gender": a ranger goes by their preferred name.
    assert_equal "#{@ranger.callsign},#{@ranger.email},Cus Gender,active," \
                 "4.00,0.00,0.00,0.00,4.00,0.00,0.00,0.00,0",
                 lines.second
  end

  test "the export carries the filters the page is showing" do
    shift(person: @ranger)
    shift(person: person(:inactive_ranger))

    get timesheets_hours_credits_path(year: YEAR, status: "inactive", format: :csv)

    assert_response :success

    lines = response.body.split("\n")

    assert_equal 2, lines.size, "only the filtered ranger should be exported"
    assert_match(/^#{person(:inactive_ranger).callsign},/, lines.second)
  end

  test "an export without the capability carries no name or email column" do
    shift
    timesheet_manager = person(:auditor_ranger)
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)
    sign_in_as(timesheet_manager)

    get timesheets_hours_credits_path(year: YEAR, format: :csv)

    assert_response :success

    lines = response.body.split("\n")

    assert_equal "Callsign,Status,#{YEAR} Total Hours,#{YEAR} Total Credits," \
                 "Pre-Event Hours,Pre-Event Credits,Event Hours,Event Credits," \
                 "Post-Event Hours,Post-Event Credits,Years", lines.first
    assert_no_match(/#{@ranger.email}/, response.body)
    assert_no_match(/Cus Gender/, response.body)
    # The ledger itself still arrives -- only the naming columns are withheld.
    assert_match(/^#{@ranger.callsign},active,4\.00,/, lines.second)
  end

  # --- the year ----------------------------------------------------------

  test "a year the selector could not offer falls back to the current year" do
    get timesheets_hours_credits_path(year: "1066")

    assert_response :success
    assert_select "h1", text: /#{YEAR} Hours & Credits/
  end
end
