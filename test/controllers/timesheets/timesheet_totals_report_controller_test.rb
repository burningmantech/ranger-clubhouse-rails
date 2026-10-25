# frozen_string_literal: true

require "test_helper"

class Timesheets::TimesheetTotalsReportControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  # A year the timesheet fixtures leave alone -- they carry 2023, 2024, and
  # 2025 entries, which would ride along in every roster and every export.
  YEAR = 2022

  setup do
    Rails.cache.clear
    Current.reset

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")

    @admin = person(:active_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)

    @position = positions(:ood_position)
    @position.update!(count_hours: true)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def create_timesheet(person, position, on_duty:, hours: 2)
    Timesheet.create!(person:, position:, on_duty:,
                      off_duty: on_duty + hours.hours,
                      additional_notes: "test shift")
  end

  def august(day, hour = 12, year: YEAR)
    Time.zone.local(year, 8, day, hour, 0, 0)
  end

  # --- Authorization ------------------------------------------------------

  test "admin and timesheet management may view the report" do
    timesheet_manager = person(:auditor_ranger)
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)

    [@admin, timesheet_manager].each do |viewer|
      sign_in_as(viewer)
      get timesheets_timesheet_totals_report_path(year: YEAR)
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  # Unlike the sibling by-callsign and by-position reports, Event Management
  # does not open this page -- upstream's policy grants it nothing here.
  test "event management alone is turned away" do
    reader = person(:echelon_ranger)
    grant_role(reader, Role::EVENT_MANAGEMENT)

    sign_in_as(reader)
    get timesheets_timesheet_totals_report_path(year: YEAR)
    assert_redirected_to me_root_path
  end

  test "a person with none of the roles is turned away" do
    sign_in_as(@outsider)
    get timesheets_timesheet_totals_report_path(year: YEAR)
    assert_redirected_to me_root_path
  end

  # --- The roster ---------------------------------------------------------

  test "the index lists one row per person with their hours and position count" do
    create_timesheet(@admin, @position, on_duty: august(25), hours: 3)
    create_timesheet(@admin, @position, on_duty: august(26), hours: 2)

    get timesheets_timesheet_totals_report_path(year: YEAR)
    assert_response :success

    assert_select "a", text: /#{@admin.callsign}/
    assert_select "a", text: /5:00 hrs • 1 position/
  end

  test "a position that does not count hours never appears" do
    @position.update!(count_hours: false)
    create_timesheet(@admin, @position, on_duty: august(25), hours: 3)

    get timesheets_timesheet_totals_report_path(year: YEAR)
    assert_response :success
    assert_select "a", text: /#{@admin.callsign}/, count: 0
  end

  test "only the chosen year is counted" do
    create_timesheet(@admin, @position, on_duty: august(25), hours: 3)
    create_timesheet(@admin, @position, on_duty: august(25, year: 2018), hours: 9)

    get timesheets_timesheet_totals_report_path(year: YEAR)
    assert_response :success
    assert_select "a", text: /3:00 hrs/
    assert_select "a", text: /12:00 hrs/, count: 0
  end

  test "the callsign filter narrows the roster" do
    other = person(:echelon_ranger)
    create_timesheet(@admin, @position, on_duty: august(25))
    create_timesheet(other, @position, on_duty: august(26))

    get timesheets_timesheet_totals_report_path(year: YEAR, callsign: @admin.callsign.downcase)
    assert_response :success
    assert_select "a", text: /#{@admin.callsign}/
    assert_select "a", text: /#{other.callsign}/, count: 0
  end

  test "a year with no qualifying timesheets says so" do
    get timesheets_timesheet_totals_report_path(year: YEAR)
    assert_response :success
    assert_select "body", text: /No #{YEAR} timesheets were turned in for positions/
  end

  # --- One person's positions ----------------------------------------------

  test "the person page lists positions and totals the hours" do
    create_timesheet(@admin, @position, on_duty: august(25), hours: 3)
    create_timesheet(@admin, @position, on_duty: august(26), hours: 2)

    get timesheets_timesheet_totals_report_person_path(@admin, year: YEAR)
    assert_response :success

    assert_select "th[data-label='Position']", text: @position.title, count: 1
    assert_select "div", text: "5:00"
  end

  test "a person id that does not exist redirects back to the roster" do
    get timesheets_timesheet_totals_report_person_path(0, year: YEAR)
    assert_redirected_to timesheets_timesheet_totals_report_path(year: YEAR)
  end

  # A real person with nothing to show this year is a true page, not a
  # missing one -- rendered rather than bounced.
  test "a real person with no qualifying entries still gets a rendered page" do
    get timesheets_timesheet_totals_report_person_path(@admin, year: YEAR)
    assert_response :success
    assert_select "body", text: /turned in no #{YEAR} timesheets/
  end

  # --- Export ---------------------------------------------------------------

  test "the export carries one row per person-position pair" do
    zebra = Position.create!(title: "Zebra Position", count_hours: true, active: true)
    create_timesheet(@admin, @position, on_duty: august(25), hours: 3)
    create_timesheet(@admin, zebra, on_duty: august(26), hours: 2)

    get timesheets_timesheet_totals_report_path(year: YEAR, format: :csv)
    assert_response :success
    assert_equal "text/csv", response.media_type

    lines = response.body.split("\n")
    assert_equal "Callsign,Status,Position,#{YEAR} Hours,#{YEAR} Credits", lines.first
    assert_equal 3, lines.size
    assert lines.any? { |line| line.include?(",#{@position.title},3.00,") }
    assert lines.any? { |line| line.include?(",Zebra Position,2.00,") }
  end

  test "the export leaves out positions that do not count hours" do
    @position.update!(count_hours: false)
    create_timesheet(@admin, @position, on_duty: august(25), hours: 3)

    get timesheets_timesheet_totals_report_path(year: YEAR, format: :csv)
    assert_response :success

    lines = response.body.split("\n")
    assert_equal 1, lines.size
  end

  test "the export carries the computed credits, not a placeholder zero" do
    PositionCredit.create!(position: @position, start_year: YEAR, end_year: YEAR,
                           start_time: august(20, 0), end_time: august(30, 0),
                           description: "Event week", credits_per_hour: 2.0)
    create_timesheet(@admin, @position, on_duty: august(25), hours: 3)

    get timesheets_timesheet_totals_report_path(year: YEAR, format: :csv)
    assert_response :success

    header, row = response.body.split("\n").map { |line| line.split(",") }
    assert_equal "3.00", row[header.index("#{YEAR} Hours")]
    assert_equal "6.00", row[header.index("#{YEAR} Credits")]
  end
end
