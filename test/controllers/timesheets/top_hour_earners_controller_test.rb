# frozen_string_literal: true

require "test_helper"

class Timesheets::TopHourEarnersControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers

  # Clear of the timesheet fixtures, which occupy 2023-2025.
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
    @outsider = person(:retired_ranger)
    @earner = person(:ranger_with_custom_gender)
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

  def shift(person: @earner, year: YEAR - 1, hours: 40, day: 25)
    on_duty = Time.zone.local(year, 8, day, 8, 0, 0)
    Timesheet.create!(person:, position: @position, on_duty:,
                      off_duty: on_duty + hours.hours, additional_notes: "test shift")
  end

  # --- who may read it ---------------------------------------------------

  # A shift first, so both readers are rendering a ranking rather than the empty
  # state -- an empty page would pass this while never reaching a single row.
  test "admin and timesheet management may view the report" do
    shift
    timesheet_manager = person(:auditor_ranger)
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)

    [@admin, timesheet_manager].each do |viewer|
      sign_in_as(viewer)
      get timesheets_top_hour_earners_path
      assert_response :success, "#{viewer.callsign} should be allowed in"
      assert_match @earner.callsign, response.body, "#{viewer.callsign} should see the ranking"
    end
  end

  # Timesheet Management is deliberately kept off the person pages, so their
  # copy of the ranking names each ranger without linking them.
  test "a reader who cannot open person pages gets plain callsigns" do
    shift
    timesheet_manager = person(:auditor_ranger)
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)
    sign_in_as(timesheet_manager)

    get timesheets_top_hour_earners_path

    assert_response :success
    assert_select "th.top-hour-earners-person", text: /#{@earner.callsign}/
    assert_select "a[href=?]", person_path(@earner), count: 0
  end

  test "an admin gets the callsign as a link to the person" do
    shift

    get timesheets_top_hour_earners_path

    assert_response :success
    assert_select "th.top-hour-earners-person a[href=?]", person_path(@earner)
  end

  test "event management is turned away from this report" do
    sign_in_as(@event_manager)

    get timesheets_top_hour_earners_path

    assert_redirected_to me_root_path
  end

  test "someone without the role is turned away" do
    sign_in_as(@outsider)

    get timesheets_top_hour_earners_path

    assert_redirected_to me_root_path
  end

  # --- the page ----------------------------------------------------------

  test "the page opens on the last five years without being asked" do
    shift

    get timesheets_top_hour_earners_path

    assert_response :success
    assert_select "th", text: (YEAR - 4).to_s
    assert_select "th", text: YEAR.to_s
    assert_select "td", text: "40.00"
    assert_match "Showing 1 person for #{YEAR - 4} to #{YEAR}", response.body
  end

  test "a span with no hours says so" do
    get timesheets_top_hour_earners_path(start_year: YEAR - 1, end_year: YEAR)

    assert_response :success
    # Not "no hours were turned in": a span can be full of hours whose earners
    # have all since retired off the roster this report ranks.
    assert_match "No active or inactive ranger earned hours on a counted position " \
                 "for #{YEAR - 1} to #{YEAR}.", response.body
  end

  # A span of one year reads as that year, not as a range from it to itself.
  test "a span of a single year is said as that year" do
    shift(year: YEAR - 1)

    get timesheets_top_hour_earners_path(start_year: YEAR - 1, end_year: YEAR - 1)

    assert_response :success
    assert_match "Showing 1 person for #{YEAR - 1}", response.body
    assert_no_match(/#{YEAR - 1} to #{YEAR - 1}/, response.body)
  end

  test "the eventless years get no column" do
    shift(year: 2022)

    get timesheets_top_hour_earners_path(start_year: 2019, end_year: 2022)

    assert_response :success
    assert_select "th", text: "2019"
    assert_select "th", text: "2022"
    assert_select "th", text: "2020", count: 0
    assert_select "th", text: "2021", count: 0
  end

  test "the ranking runs highest first" do
    shift(person: @earner, hours: 40)
    shift(person: @admin, hours: 80)

    get timesheets_top_hour_earners_path

    assert_response :success
    # The frozen first cell of each row carries the rank and the callsign.
    callsigns = css_select("th.top-hour-earners-person").map { |cell| cell.text.strip }
    assert_match(/\A1\.\s+#{@admin.callsign}/, callsigns[1])
    assert_match(/\A2\.\s+#{@earner.callsign}/, callsigns[2])
  end

  # A parameter can arrive as an array or a nested hash from a hand-edited URL,
  # and neither may take the page down.
  test "a parameter that is not a number leaves the page standing" do
    shift

    get timesheets_top_hour_earners_path(start_year: ["x"], end_year: { "a" => "b" },
                                         limit: ["y"])

    assert_response :success
    assert_match "Showing 1 person for #{YEAR - 4} to #{YEAR}", response.body
  end

  # --- the export --------------------------------------------------------

  test "the export carries the span on screen" do
    shift

    get timesheets_top_hour_earners_path(start_year: YEAR - 2, end_year: YEAR, format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match "top-hour-earners-#{YEAR - 2}-#{YEAR}.csv",
                 response.headers["Content-Disposition"]

    lines = response.body.split("\n")

    assert_equal "Callsign,Name,Status,Email,Top Hours,Top Year," \
                 "#{YEAR - 2},#{YEAR - 1},#{YEAR}", lines.first
    # "Cus Gender", not "Custom Gender": a ranger goes by their preferred name.
    assert_equal "#{@earner.callsign},Cus Gender,active,#{@earner.email}," \
                 "40.00,#{YEAR - 1},0.00,40.00,0.00", lines.second
  end

  test "the export names a ranger with no preferred name by their first name" do
    shift(person: @admin)

    get timesheets_top_hour_earners_path(format: :csv)

    assert_response :success
    assert_match(/^#{@admin.callsign},Test Ranger,/, response.body)
  end

  # Reading the ranking does not carry permission to see who people are off the
  # playa. Timesheet Management holds neither capability, so their copy of the
  # export names rangers by callsign alone.
  test "a reader without the capability gets no name or email column" do
    shift
    timesheet_manager = person(:auditor_ranger)
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)
    sign_in_as(timesheet_manager)

    get timesheets_top_hour_earners_path(format: :csv)

    assert_response :success

    lines = response.body.split("\n")

    assert_equal "Callsign,Status,Top Hours,Top Year," \
                 "#{YEAR - 4},#{YEAR - 3},#{YEAR - 2},#{YEAR - 1},#{YEAR}", lines.first
    assert_no_match(/#{@earner.email}/, response.body)
    assert_no_match(/Cus Gender/, response.body)
    # The ranking itself still arrives -- only the naming columns are withheld.
    assert_match(/^#{@earner.callsign},active,40\.00,/, lines.second)
  end

  test "the export leaves out the eventless years the page leaves out" do
    shift(year: 2022)

    get timesheets_top_hour_earners_path(start_year: 2019, end_year: 2022, format: :csv)

    assert_response :success
    assert_equal "Callsign,Name,Status,Email,Top Hours,Top Year,2019,2022",
                 response.body.split("\n").first
  end
end
