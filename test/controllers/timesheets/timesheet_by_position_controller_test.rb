# frozen_string_literal: true

require "test_helper"

class Timesheets::TimesheetByPositionControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  # A year the timesheet fixtures leave alone -- they carry 2023, 2024, and 2025
  # entries, which would ride along in every index and every export.
  YEAR = 2022

  setup do
    Rails.cache.clear
    Current.reset

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::FULL_REPORT_ACCESS, "Full Report Access")

    @admin = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)

    # council_manager belongs to council_cadre, khaki_supervisor to the khaki
    # delegation. ood_position belongs to no team at all, so it is only ever
    # visible to a full-report reader.
    @council_position = positions(:council_manager)
    @khaki_position = positions(:khaki_supervisor)
    @unowned_position = positions(:ood_position)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # additional_notes is required on every Timesheet.
  def create_timesheet(person, position, on_duty:, hours: 2)
    Timesheet.create!(person:, position:, on_duty:,
                      off_duty: on_duty + hours.hours,
                      additional_notes: "test shift")
  end

  def august(day, hour = 12, year: YEAR)
    Time.zone.local(year, 8, day, hour, 0, 0)
  end

  # A reader gated to one Cadre's positions: Timesheet Management passes the
  # controller but is neither Admin nor Full Report Access.
  def build_partial_reader
    reader = person(:auditor_ranger)
    grant_role(reader, Role::TIMESHEET_MANAGEMENT)
    PersonTeam.create!(person: reader, team: teams(:council_cadre))
    reader
  end

  # --- Authorization ------------------------------------------------------

  # Upstream TimesheetPolicy: before admits Admin and Timesheet Management,
  # timesheetByPosition() admits Event Management.
  test "admin, timesheet management, and event management may all view the report" do
    timesheet_manager = person(:auditor_ranger)
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)

    [@admin, @event_manager, timesheet_manager].each do |viewer|
      sign_in_as(viewer)
      get timesheets_timesheet_by_position_path(year: YEAR)
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "a person with none of the three roles is turned away" do
    sign_in_as(@outsider)
    get timesheets_timesheet_by_position_path(year: YEAR)
    assert_redirected_to me_root_path
  end

  # Full Report Access widens which positions are shown; it is not a key to the
  # page itself.
  test "full report access alone does not open the page" do
    reader = person(:retired_ranger)
    grant_role(reader, Role::FULL_REPORT_ACCESS)

    sign_in_as(reader)
    get timesheets_timesheet_by_position_path(year: YEAR)
    assert_redirected_to me_root_path
  end

  # --- The index ----------------------------------------------------------

  test "the index lists one row per position with its hours and counts" do
    create_timesheet(@admin, @unowned_position, on_duty: august(25), hours: 3)
    create_timesheet(@event_manager, @unowned_position, on_duty: august(26), hours: 2)
    create_timesheet(@admin, @council_position, on_duty: august(27), hours: 4)

    get timesheets_timesheet_by_position_path(year: YEAR)
    assert_response :success

    assert_select "a", text: /#{Regexp.escape(@unowned_position.title)}/
    assert_select "a", text: /5:00 hrs • 2 entries • 2 rangers/
    assert_select "a", text: /#{Regexp.escape(@council_position.title)}/
    assert_select "a", text: /4:00 hrs • 1 entry • 1 ranger/
  end

  test "only the chosen year is counted" do
    create_timesheet(@admin, @unowned_position, on_duty: august(25), hours: 3)
    create_timesheet(@admin, @unowned_position, on_duty: august(25, year: 2018), hours: 9)

    get timesheets_timesheet_by_position_path(year: YEAR)
    assert_response :success
    assert_select "a", text: /3:00 hrs • 1 entry/
    assert_select "a", text: /12:00 hrs/, count: 0
  end

  test "the title filter narrows the index" do
    create_timesheet(@admin, @unowned_position, on_duty: august(25))
    create_timesheet(@admin, @council_position, on_duty: august(26))

    get timesheets_timesheet_by_position_path(year: YEAR,
                                              title: @unowned_position.title.downcase)
    assert_response :success
    assert_select "a", text: /#{Regexp.escape(@unowned_position.title)}/
    assert_select "a", text: /#{Regexp.escape(@council_position.title)}/, count: 0
  end

  test "the status filter separates active positions from inactive ones" do
    @unowned_position.update!(active: false)
    create_timesheet(@admin, @unowned_position, on_duty: august(25))
    create_timesheet(@admin, @council_position, on_duty: august(26))

    get timesheets_timesheet_by_position_path(year: YEAR, active: "inactive")
    assert_response :success
    assert_select "a", text: /#{Regexp.escape(@unowned_position.title)}/
    assert_select "a", text: /#{Regexp.escape(@council_position.title)}/, count: 0
  end

  # The exception is badged; an "Active" chip on every one of 140 rows says
  # nothing.
  test "an inactive position is badged on the index" do
    @unowned_position.update!(active: false)
    create_timesheet(@admin, @unowned_position, on_duty: august(25))

    get timesheets_timesheet_by_position_path(year: YEAR)
    assert_response :success
    assert_select "a", text: /Inactive/
  end

  test "a year with no timesheets says so" do
    get timesheets_timesheet_by_position_path(year: YEAR)
    assert_response :success
    assert_select "body", text: /No #{YEAR} timesheets were turned in/
  end

  # --- Partial-report scoping ---------------------------------------------

  test "a partial reader sees only the positions their teams own" do
    reader = build_partial_reader
    create_timesheet(@admin, @council_position, on_duty: august(25), hours: 3)
    create_timesheet(@event_manager, @unowned_position, on_duty: august(26), hours: 4)

    sign_in_as(reader)
    get timesheets_timesheet_by_position_path(year: YEAR)
    assert_response :success

    assert_select "a", text: /#{Regexp.escape(@council_position.title)}/
    assert_select "a", text: /3:00 hrs/
    assert_select "a", text: /#{Regexp.escape(@unowned_position.title)}/, count: 0
    assert_select "body", text: /Some Positions Are Hidden/
  end

  # Upstream only ever scoped one bulk query. The drill-down adds a second entry
  # point, and it has to be scoped the same way or the URL is a hole.
  test "a partial reader cannot read a hidden position's entries by URL" do
    reader = build_partial_reader
    create_timesheet(@event_manager, @unowned_position, on_duty: august(26), hours: 4)

    sign_in_as(reader)
    get timesheets_timesheet_by_position_position_path(@unowned_position.id, year: YEAR)
    assert_redirected_to timesheets_timesheet_by_position_path(year: YEAR)
  end

  # The same answer for a position that cannot be seen as for one that does not
  # exist, or the difference between the two is an id oracle.
  test "a scoped reader cannot tell a hidden position from a missing one" do
    reader = build_partial_reader
    sign_in_as(reader)

    get timesheets_timesheet_by_position_position_path(@unowned_position.id, year: YEAR)
    hidden = flash[:error]
    get timesheets_timesheet_by_position_position_path(0, year: YEAR)

    assert_equal hidden, flash[:error]
    assert_no_match(/#{Regexp.escape(@unowned_position.title)}/, hidden.to_s)
  end

  # Asked of the scope rather than inferred from an empty result: a position the
  # reader's own Cadre owns is theirs to read even in a year no one rangered it,
  # and "could not be found" would be a lie about their own team.
  test "a partial reader may open their own position in a year with no entries" do
    reader = build_partial_reader
    sign_in_as(reader)

    get timesheets_timesheet_by_position_position_path(@council_position.id, year: YEAR)
    assert_response :success
    assert_select "body", text: /No #{YEAR} timesheets were turned in for #{Regexp.escape(@council_position.title)}/
  end

  test "a reader belonging to no position-owning team is told so" do
    reader = person(:retired_ranger)
    grant_role(reader, Role::TIMESHEET_MANAGEMENT)
    create_timesheet(@admin, @unowned_position, on_duty: august(25))

    sign_in_as(reader)
    get timesheets_timesheet_by_position_path(year: YEAR)
    assert_response :success

    assert_select "body", text: /No Positions to Show/
    assert_select "a", text: /#{Regexp.escape(@unowned_position.title)}/, count: 0
  end

  # A managed team counts the same as a Cadre membership.
  test "a team manager sees their team's positions" do
    reader = person(:retired_ranger)
    grant_role(reader, Role::TIMESHEET_MANAGEMENT)
    TeamManager.create!(person: reader, team: teams(:khaki_team))
    create_timesheet(@admin, @khaki_position, on_duty: august(25), hours: 6)

    sign_in_as(reader)
    get timesheets_timesheet_by_position_path(year: YEAR)
    assert_response :success
    assert_select "a", text: /6:00 hrs/
  end

  # --- One position's entries ---------------------------------------------

  test "the position page lists the entries and totals the hours" do
    create_timesheet(@admin, @unowned_position, on_duty: august(25), hours: 3)
    create_timesheet(@event_manager, @unowned_position, on_duty: august(26), hours: 2)

    get timesheets_timesheet_by_position_position_path(@unowned_position.id, year: YEAR)
    assert_response :success

    assert_select "th[data-label='Callsign']", count: 2
    # The stat box, named exactly: the entries themselves run 12:00 to 15:00 and
    # to 14:00, so a loose /5:00/ matches "15:00" and stays green however wrong
    # the total goes.
    assert_select "div", text: "5:00"
  end

  # count_hours false still earns credits -- it only stops counting toward
  # provisions, and it is a property of the whole position rather than of some
  # of its rows.
  test "a position whose hours do not buy provisions says so once" do
    @unowned_position.update!(count_hours: false)
    create_timesheet(@admin, @unowned_position, on_duty: august(25), hours: 3)

    get timesheets_timesheet_by_position_position_path(@unowned_position.id, year: YEAR)
    assert_response :success
    assert_select "body", text: /do not count toward provisions and appreciations/
  end

  test "a position id that does not exist redirects back to the index" do
    get timesheets_timesheet_by_position_position_path(0, year: YEAR)
    assert_redirected_to timesheets_timesheet_by_position_path(year: YEAR)
  end

  # --- Exports ------------------------------------------------------------

  test "the index exports every visible entry with its position" do
    create_timesheet(@admin, @unowned_position, on_duty: august(25), hours: 3)
    create_timesheet(@event_manager, @council_position, on_duty: august(26), hours: 4)

    get timesheets_timesheet_by_position_path(year: YEAR, format: :csv)
    assert_response :success
    assert_equal "text/csv", response.media_type

    lines = response.body.split("\n")
    assert_equal "Position,From,To,Hours,Credits,Callsign,Status," \
                 "Shift Begins,Shift Duration,Shift Description,Email", lines.first
    assert_equal 3, lines.size
    assert lines.any? { |line| line.start_with?("#{@unowned_position.title},") }
  end

  test "a position's export carries only its own entries and drops the position column" do
    create_timesheet(@admin, @unowned_position, on_duty: august(25), hours: 3)
    create_timesheet(@event_manager, @council_position, on_duty: august(26), hours: 4)

    get timesheets_timesheet_by_position_position_path(@unowned_position.id, year: YEAR,
                                                       format: :csv)
    assert_response :success

    lines = response.body.split("\n")
    assert_equal 2, lines.size
    assert_equal "From,To,Hours,Credits,Callsign,Status," \
                 "Shift Begins,Shift Duration,Shift Description,Email", lines.first
    assert lines.last.include?(@admin.callsign)
  end

  # Upstream declares a Status column its export builder never fills, so every
  # row carries a blank. This port fills it.
  test "the export names each ranger's status" do
    create_timesheet(@admin, @unowned_position, on_duty: august(25), hours: 3)

    get timesheets_timesheet_by_position_position_path(@unowned_position.id, year: YEAR,
                                                       format: :csv)
    assert_response :success

    header, row = response.body.split("\n").map { |line| line.split(",") }
    assert_equal @admin.status, row[header.index("Status")]
  end

  # Both hour columns and the credits column are two-decimal numbers, so an
  # assertion on the text alone cannot tell them apart. Split the row and name
  # the column, or a credits regression reads as green forever.
  test "the export carries the computed credits, not a placeholder zero" do
    PositionCredit.create!(position: @unowned_position, start_year: YEAR, end_year: YEAR,
                           start_time: august(20, 0), end_time: august(30, 0),
                           description: "Event week", credits_per_hour: 2.0)
    create_timesheet(@admin, @unowned_position, on_duty: august(25), hours: 3)

    get timesheets_timesheet_by_position_position_path(@unowned_position.id, year: YEAR,
                                                       format: :csv)
    assert_response :success

    header, row = response.body.split("\n").map { |line| line.split(",") }
    assert_equal "3.00", row[header.index("Hours")]
    assert_equal "6.00", row[header.index("Credits")]
  end

  test "a partial reader's export is scoped the same way the page is" do
    reader = build_partial_reader
    create_timesheet(@admin, @council_position, on_duty: august(25), hours: 3)
    create_timesheet(@event_manager, @unowned_position, on_duty: august(26), hours: 4)

    sign_in_as(reader)
    get timesheets_timesheet_by_position_path(year: YEAR, format: :csv)
    assert_response :success

    lines = response.body.split("\n")
    assert_equal 2, lines.size
    assert lines.last.start_with?("#{@council_position.title},")
  end

  # The email column is the viewer's, not the page's: Timesheet Management
  # passes the gate without Admin/VC/View Email behind it.
  test "the email column appears only for a reader who may see emails" do
    create_timesheet(@admin, @unowned_position, on_duty: august(25), hours: 3)

    get timesheets_timesheet_by_position_position_path(@unowned_position.id, year: YEAR,
                                                       format: :csv)
    assert_response :success
    assert_includes response.body.split("\n").first, "Email"

    reader = person(:auditor_ranger)
    grant_role(reader, Role::TIMESHEET_MANAGEMENT)
    PersonTeam.create!(person: reader, team: teams(:council_cadre))
    create_timesheet(@admin, @council_position, on_duty: august(25), hours: 3)

    sign_in_as(reader)
    get timesheets_timesheet_by_position_position_path(@council_position.id, year: YEAR,
                                                       format: :csv)
    # Asserted before the negative: a redirect body has no "Email" either, so
    # without this a scoping regression would read as an email-column pass.
    assert_response :success
    assert_not_includes response.body.split("\n").first, "Email"
  end

  # --- Position-level notices ---------------------------------------------

  test "an inactive position says so on its page" do
    @unowned_position.update!(active: false)
    create_timesheet(@admin, @unowned_position, on_duty: august(25))

    get timesheets_timesheet_by_position_position_path(@unowned_position.id, year: YEAR)
    assert_response :success
    assert_select "body", text: /This Position Is Inactive/
  end

  # The notice describes the position, not its rows, so it stands in a year the
  # position collected nothing.
  test "the inactive notice shows even with no entries that year" do
    @unowned_position.update!(active: false)

    get timesheets_timesheet_by_position_position_path(@unowned_position.id, year: YEAR)
    assert_response :success
    assert_select "body", text: /This Position Is Inactive/
  end

  test "a position whose hours do not buy provisions is badged on the index" do
    @unowned_position.update!(count_hours: false)
    create_timesheet(@admin, @unowned_position, on_duty: august(25))

    get timesheets_timesheet_by_position_path(year: YEAR)
    assert_response :success
    assert_select "a", text: /No provisions/
  end

  # A timesheet outlives its position -- the schema carries no FK. The row still
  # has to show the hours, but it must not offer a link that only ever bounces.
  test "a deleted position's row is shown but cannot be followed" do
    timesheet = create_timesheet(@admin, @unowned_position, on_duty: august(25))
    timesheet.update_columns(position_id: 0)

    get timesheets_timesheet_by_position_path(year: YEAR)
    assert_response :success

    assert_select "body", text: /Position #0/
    assert_select "body", text: /This position has been deleted/
    assert_select "a[href*='/position/0']", count: 0
  end
end
