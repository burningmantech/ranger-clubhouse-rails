# frozen_string_literal: true

require "test_helper"

class Timesheets::TimesheetsByCallsignControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ReportCardTestHelper     # assert_report_card

  # A year the timesheet fixtures leave alone -- they carry 2023, 2024, and 2025
  # entries, which would ride along in every roster and every export.
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
  # timesheetByCallsign() admits Event Management.
  test "admin, timesheet management, and event management may all view the report" do
    timesheet_manager = person(:auditor_ranger)
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)

    [@admin, @event_manager, timesheet_manager].each do |viewer|
      sign_in_as(viewer)
      get timesheets_timesheets_by_callsign_path(year: YEAR)
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "a person with none of the three roles is turned away" do
    sign_in_as(@outsider)
    get timesheets_timesheets_by_callsign_path(year: YEAR)
    assert_redirected_to me_root_path
  end

  # Full Report Access widens which positions are shown; it is not a key to the
  # page itself.
  test "full report access alone does not open the page" do
    reader = person(:retired_ranger)
    grant_role(reader, Role::FULL_REPORT_ACCESS)

    sign_in_as(reader)
    get timesheets_timesheets_by_callsign_path(year: YEAR)
    assert_redirected_to me_root_path
  end

  # --- The roster ---------------------------------------------------------

  test "the index lists one row per person with their hours and entry count" do
    create_timesheet(@admin, @unowned_position, on_duty: august(25), hours: 3)
    create_timesheet(@admin, @unowned_position, on_duty: august(26), hours: 2)
    create_timesheet(@event_manager, @unowned_position, on_duty: august(27), hours: 4)

    get timesheets_timesheets_by_callsign_path(year: YEAR)
    assert_response :success

    assert_select "a", text: /#{@admin.callsign}/
    assert_select "a", text: /5:00 hrs • 2 entries/
    assert_select "a", text: /#{@event_manager.callsign}/
    assert_select "a", text: /4:00 hrs • 1 entry/
  end

  test "only the chosen year is counted" do
    create_timesheet(@admin, @unowned_position, on_duty: august(25), hours: 3)
    create_timesheet(@admin, @unowned_position, on_duty: august(25, year: 2018), hours: 9)

    get timesheets_timesheets_by_callsign_path(year: YEAR)
    assert_response :success
    assert_select "a", text: /3:00 hrs • 1 entry/
    assert_select "a", text: /12:00 hrs/, count: 0
  end

  test "the callsign filter narrows the roster" do
    create_timesheet(@admin, @unowned_position, on_duty: august(25))
    create_timesheet(@event_manager, @unowned_position, on_duty: august(26))

    get timesheets_timesheets_by_callsign_path(year: YEAR, callsign: @admin.callsign.downcase)
    assert_response :success
    assert_select "a", text: /#{@admin.callsign}/
    assert_select "a", text: /#{@event_manager.callsign}/, count: 0
  end

  test "a year with no timesheets says so" do
    get timesheets_timesheets_by_callsign_path(year: YEAR)
    assert_response :success
    assert_select "body", text: /No #{YEAR} timesheets were turned in/
  end

  # --- Partial-report scoping ---------------------------------------------

  test "a partial reader sees only the positions their teams own" do
    reader = build_partial_reader
    create_timesheet(@admin, @council_position, on_duty: august(25), hours: 3)
    create_timesheet(@event_manager, @unowned_position, on_duty: august(26), hours: 4)

    sign_in_as(reader)
    get timesheets_timesheets_by_callsign_path(year: YEAR)
    assert_response :success

    assert_select "a", text: /#{@admin.callsign}/
    assert_select "a", text: /3:00 hrs/
    assert_select "a", text: /#{@event_manager.callsign}/, count: 0
    assert_select "body", text: /Some Positions Are Hidden/
  end

  # Upstream only ever scoped one bulk query. The drill-down adds a second
  # entry point, and it has to be scoped the same way or the URL is a hole.
  #
  # Turned back rather than shown an empty page: rendering it would put the
  # callsign in the heading, and a reader who may not open /person/:id must not
  # be handed a person page under another name.
  test "a partial reader cannot read a hidden position's entries by URL" do
    reader = build_partial_reader
    create_timesheet(@event_manager, @unowned_position, on_duty: august(26), hours: 4)

    sign_in_as(reader)
    get timesheets_timesheets_by_callsign_person_path(@event_manager, year: YEAR)
    assert_redirected_to timesheets_timesheets_by_callsign_path(year: YEAR)
  end

  # The same answer for a person who cannot be seen as for one who does not
  # exist, or the difference between the two is an id oracle.
  test "a scoped reader cannot tell a hidden person from a missing one" do
    reader = build_partial_reader
    sign_in_as(reader)

    get timesheets_timesheets_by_callsign_person_path(@event_manager, year: YEAR)
    hidden = flash[:error]
    get timesheets_timesheets_by_callsign_person_path(0, year: YEAR)

    assert_equal hidden, flash[:error]
    assert_no_match(/#{@event_manager.callsign}/, hidden.to_s)
  end

  # A full-report reader seeing an empty year is reading a true page, so it is
  # rendered rather than bounced.
  test "a full report reader still sees a person page with no entries" do
    get timesheets_timesheets_by_callsign_person_path(@event_manager, year: YEAR)
    assert_response :success
    assert_select "body", text: /turned in no #{YEAR} timesheets/
  end

  test "a reader belonging to no position-owning team is told so" do
    reader = person(:retired_ranger)
    grant_role(reader, Role::TIMESHEET_MANAGEMENT)
    create_timesheet(@admin, @unowned_position, on_duty: august(25))

    sign_in_as(reader)
    get timesheets_timesheets_by_callsign_path(year: YEAR)
    assert_response :success

    assert_select "body", text: /No Positions to Show/
    assert_select "a", text: /#{@admin.callsign}/, count: 0
  end

  # A managed team counts the same as a Cadre membership.
  test "a team manager sees their team's positions" do
    reader = person(:retired_ranger)
    grant_role(reader, Role::TIMESHEET_MANAGEMENT)
    TeamManager.create!(person: reader, team: teams(:khaki_team))
    create_timesheet(@admin, @khaki_position, on_duty: august(25), hours: 6)

    sign_in_as(reader)
    get timesheets_timesheets_by_callsign_path(year: YEAR)
    assert_response :success
    assert_select "a", text: /6:00 hrs/
  end

  # --- One person's entries -----------------------------------------------

  test "the person page lists the entries and totals the hours" do
    create_timesheet(@admin, @unowned_position, on_duty: august(25), hours: 3)
    create_timesheet(@admin, @unowned_position, on_duty: august(26), hours: 2)

    get timesheets_timesheets_by_callsign_person_path(@admin, year: YEAR)
    assert_response :success

    assert_select "td[data-label='Position']", text: @unowned_position.title, count: 2
    assert_select "body", text: /5:00/
    # The card holds the ban icon's legend and nothing else, and no row here
    # carries the icon.
    assert_report_card count: 0
  end

  # count_hours false still earns credits -- it only stops counting toward
  # provisions, which is why the two hour totals differ.
  test "hours in a position that does not count are tracked separately" do
    @unowned_position.update!(count_hours: false)
    create_timesheet(@admin, @unowned_position, on_duty: august(25), hours: 3)
    create_timesheet(@admin, @council_position, on_duty: august(26), hours: 2)

    get timesheets_timesheets_by_callsign_person_path(@admin, year: YEAR)
    assert_response :success

    # The stat boxes: total hours, then the hours that count toward provisions.
    assert_select "div", text: "5:00"
    assert_select "div", text: "2:00"
    assert_report_card
    assert_select "details dd", text: /do not count toward provisions and appreciations/
    # The sentence is folded away, so the one marked row says it for itself.
    assert_select "td i.fa-ban[title='Does not count toward provisions']", count: 1
    assert_select "td span.sr-only", text: "Does not count toward provisions.", count: 1
  end

  test "a person id that does not exist redirects back to the roster" do
    get timesheets_timesheets_by_callsign_person_path(0, year: YEAR)
    assert_redirected_to timesheets_timesheets_by_callsign_path(year: YEAR)
  end

  # --- Exports ------------------------------------------------------------

  test "the roster exports every visible entry" do
    create_timesheet(@admin, @unowned_position, on_duty: august(25), hours: 3)
    create_timesheet(@event_manager, @unowned_position, on_duty: august(26), hours: 4)

    get timesheets_timesheets_by_callsign_path(year: YEAR, format: :csv)
    assert_response :success
    assert_equal "text/csv", response.media_type

    lines = response.body.split("\n")
    assert_equal "Callsign,Status,From,To,Hours,Credits,Position,Count Hours," \
                 "Shift Begins,Shift Duration,Shift Description", lines.first
    assert_equal 3, lines.size
    assert lines.any? { |line| line.start_with?("#{@admin.callsign},") }
    assert lines.any? { |line| line.include?(",3.00,") }
  end

  test "a person's export carries only their own entries" do
    create_timesheet(@admin, @unowned_position, on_duty: august(25), hours: 3)
    create_timesheet(@event_manager, @unowned_position, on_duty: august(26), hours: 4)

    get timesheets_timesheets_by_callsign_person_path(@admin, year: YEAR, format: :csv)
    assert_response :success

    lines = response.body.split("\n")
    assert_equal 2, lines.size
    assert lines.last.start_with?("#{@admin.callsign},")
  end

  # Both hour columns and the credits column are two-decimal numbers, so an
  # assertion on the text alone cannot tell them apart. Split the row and name
  # the column, or a credits regression reads as green forever.
  test "the export carries the computed credits, not a placeholder zero" do
    PositionCredit.create!(position: @unowned_position, start_year: YEAR, end_year: YEAR,
                           start_time: august(20, 0), end_time: august(30, 0),
                           description: "Event week", credits_per_hour: 2.0)
    create_timesheet(@admin, @unowned_position, on_duty: august(25), hours: 3)

    get timesheets_timesheets_by_callsign_person_path(@admin, year: YEAR, format: :csv)
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
    get timesheets_timesheets_by_callsign_path(year: YEAR, format: :csv)
    assert_response :success

    lines = response.body.split("\n")
    assert_equal 2, lines.size
    assert lines.last.start_with?("#{@admin.callsign},")
  end
end
