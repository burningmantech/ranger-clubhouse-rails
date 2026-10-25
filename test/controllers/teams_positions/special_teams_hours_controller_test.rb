# frozen_string_literal: true

require "test_helper"

class TeamsPositions::SpecialTeamsHoursControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper
  include ActiveSupport::Testing::TimeHelpers

  CONTROLLER = TeamsPositions::SpecialTeamsHoursController

  # Clear of the timesheet fixtures, which occupy 2023-2025.
  YEAR = 2031

  setup do
    Rails.cache.clear
    Current.reset
    travel_to Time.zone.local(YEAR, 8, 26, 12, 0, 0)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")

    @admin = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @outsider = person(:retired_ranger)
    @earner = person(:ranger_with_custom_gender)
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)

    # On a team, so the picker has a group to open for it.
    @green = Position.create!(title: "Test Green Dot", active: true, type: Position::TYPE_FRONTLINE,
                              team: teams(:khaki_team))

    sign_in_as(@admin)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  def shift(person: @earner, year: YEAR, hours: 6)
    on_duty = Time.local(year, 8, 20, 9)
    Timesheet.create!(person:, position: @green, on_duty:, off_duty: on_duty + hours.hours,
                      additional_notes: "test shift")
  end

  # The request the page's own form sends: the span and options in the report
  # scope, and the chosen positions as top-level ids[].
  def report_params(ids: [@green.id], **options)
    { report: { start_year: YEAR - 1, end_year: YEAR, **options }, ids: }
  end

  def parameters_card = css_select("details").find { |details| details.text.include?("Report Parameters") }

  # The page draws this many people at most. Swapped for the length of a block
  # so the cap can be crossed with two people rather than five hundred.
  def with_row_limit(limit)
    original = CONTROLLER::ROW_LIMIT
    CONTROLLER.send(:remove_const, :ROW_LIMIT)
    CONTROLLER.const_set(:ROW_LIMIT, limit)
    yield
  ensure
    CONTROLLER.send(:remove_const, :ROW_LIMIT)
    CONTROLLER.const_set(:ROW_LIMIT, original)
  end

  # ---------------------------------------------------------------- access

  test "denies access without the admin or event management role" do
    sign_in_as(@outsider)
    get teams_positions_special_teams_hours_path

    assert_redirected_to me_root_path
  end

  test "allows event management" do
    shift
    sign_in_as(@event_manager)
    get teams_positions_special_teams_hours_path(report_params)

    assert_response :success
    assert_select "tbody th", text: /#{@earner.callsign}/
  end

  # ------------------------------------------------------------------ page

  test "opens on the parameters with nothing run" do
    get teams_positions_special_teams_hours_path

    assert_response :success
    assert_select "h1", /Special Teams Hours/
    assert parameters_card["open"], "the parameters are open while nothing has run"
    assert_select "input[type=checkbox][name=?][value=?]", "ids[]", @green.id.to_s
    assert_select "table", count: 0
    assert_not_includes response.body, "Choose at least one position"
  end

  test "runs the report for the chosen positions and span" do
    shift(year: YEAR - 1, hours: 6)
    shift(year: YEAR, hours: 4)

    get teams_positions_special_teams_hours_path(report_params)

    assert_response :success
    assert_select "th", text: "#{YEAR - 1} Hours"
    assert_select "th", text: "#{YEAR} Hours"
    assert_select "tbody tr" do |rows|
      earner = rows.find { |row| row.text.include?(@earner.callsign) }
      assert earner, "the earner has a row"
      assert_match(/6\.00.*4\.00.*10\.00/m, earner.text)
    end
    assert_match "Showing 1 person for Test Green Dot, #{YEAR - 1} to #{YEAR}", response.body
    assert_nil parameters_card["open"], "folded to its summary line once a report has run"

    # The chosen position is checked, and its team opened to show it.
    assert_select "input#special-teams-position-#{@green.id}[checked]"
    assert_select "details[open] > summary", text: teams(:khaki_team).title
    # The picker's count arrives rendered.
    assert_select "[data-position-picker-target=count]",
                  text: "1 of #{css_select("[data-position-picker-target=checkbox]").size} selected"
    assert_unique_dom_ids
  end

  # Folded into cards on a phone, each figure is labelled by the heading above
  # it, so the totals row's spanning label must not shift them.
  test "the totals row lines up with the columns above it" do
    shift(year: YEAR - 1, hours: 6)
    shift(year: YEAR, hours: 4)

    get teams_positions_special_teams_hours_path(report_params)

    totals = css_select("tbody tr").last
    assert_equal "Totals", totals.at_css("th").text.strip
    assert_equal "6.00", totals.at_css("td[data-label='#{YEAR - 1} Hours']").text.strip
    assert_equal "10.00", totals.at_css("td[data-label='Total Hours']").text.strip
  end

  test "asks for a position when none was chosen" do
    get teams_positions_special_teams_hours_path(report: { start_year: YEAR, end_year: YEAR })

    assert_response :success
    assert_match "Choose at least one position to report on.", response.body
    assert_select "table", count: 0
  end

  # "0" and the id of a position since removed name nothing, so they are no
  # position chosen -- not a report that runs and finds no one.
  test "ids that name no position count as none chosen" do
    get teams_positions_special_teams_hours_path(report_params(ids: ["0", "999999"]))

    assert_response :success
    assert_match "Choose at least one position to report on.", response.body
    assert_select "table", count: 0

    shift
    get teams_positions_special_teams_hours_path(report_params(ids: [@green.id, 999_999]))

    assert_select "tbody th", text: /#{@earner.callsign}/
    assert_match(/· 1 position(?!s)/, parameters_card.text, "the summary counts the position that exists")
  end

  test "ids that are not ids count as none chosen" do
    get teams_positions_special_teams_hours_path(report_params(ids: ["abc", "", "7x"]))

    assert_response :success
    assert_match "Choose at least one position to report on.", response.body
    assert_select "table", count: 0
  end

  # A hand-written or shortened link may name one position as a plain value.
  test "a single ids value runs the report" do
    shift

    get teams_positions_special_teams_hours_path(ids: @green.id.to_s)

    assert_response :success
    assert_select "tbody th", text: /#{@earner.callsign}/
  end

  test "says so when nobody matched" do
    get teams_positions_special_teams_hours_path(report_params)

    assert_response :success
    assert_match "No one signed in to the chosen positions from #{YEAR - 1} to #{YEAR}. " \
                 "Deceased, dismissed, resigned, suspended, and uberbonked accounts are never listed.",
                 response.body
    assert_select "table", count: 0
    # Folded, so the answer sits just under the hero instead of below the picker.
    assert_nil parameters_card["open"]
  end

  # Nothing else on the page says what was reported on once the picker folds.
  test "names every chosen position, or says when all of them were" do
    shift
    extras = Array.new(5) { |i| Position.create!(title: "Test Extra #{i}", active: true, type: Position::TYPE_FRONTLINE) }

    get teams_positions_special_teams_hours_path(report_params(ids: [@green.id, *extras.map(&:id)]))
    assert_match "Test Extra 4", css_select("main p").map(&:text).join

    get teams_positions_special_teams_hours_path(report_params(ids: Position.pluck(:id)))
    assert_match "for all #{Position.count} positions", response.body
  end

  test "the year menus show the span that ran" do
    get teams_positions_special_teams_hours_path(report: { start_year: 2009, end_year: 2021 }, ids: [@green.id])

    assert_select "select[name='report[start_year]'] option[selected]", text: "2010"
    assert_select "select[name='report[end_year]'] option[selected]", text: "2022"
  end

  test "teamless positions come first as General Positions, and retired ones say so" do
    Position.create!(title: "Test Retired Spot", active: false, type: Position::TYPE_OTHER)

    get teams_positions_special_teams_hours_path

    groups = css_select("[data-controller=position-picker] details > summary").map { |summary| summary.text.strip }
    assert_equal "General Positions", groups.first
    assert_select "label", text: /Test Retired Spot \(inactive\)/
  end

  test "past the row limit the page stops, says so, and still totals everyone" do
    shift(person: @earner, hours: 6)
    shift(person: @admin, hours: 4)

    with_row_limit(1) do
      get teams_positions_special_teams_hours_path(report_params)
    end

    assert_response :success
    assert_select "tbody tr", count: 2, message: "one person and the totals"
    assert_match "Showing the First 1", response.body
    assert_match "Showing 1 of 2 people", response.body
    totals = css_select("tbody tr").last
    assert_equal "Totals for All 2", totals.at_css("th").text.strip
    assert_equal "10.00", totals.at_css("td[data-label='Total Hours']").text.strip
  end

  test "sign-up columns appear only when asked for" do
    shift

    get teams_positions_special_teams_hours_path(report_params)
    assert_response :success
    assert_select "tbody th", text: /#{@earner.callsign}/
    assert_select "th", text: "#{YEAR} Sign-Ups", count: 0
    assert_select "th", text: "Total Sign-Ups", count: 0

    get teams_positions_special_teams_hours_path(report_params(show_signups: "1"))
    assert_select "th", text: "#{YEAR} Sign-Ups"
    assert_select "th", text: "Total Sign-Ups"
  end

  test "names and email addresses only for a reader allowed to see them" do
    shift

    get teams_positions_special_teams_hours_path(report_params)
    assert_select "th", text: "Name"
    assert_select "th", text: "Email"

    sign_in_as(@event_manager)
    get teams_positions_special_teams_hours_path(report_params)
    assert_response :success
    assert_select "tbody th", text: /#{@earner.callsign}/
    assert_select "th", text: "Name", count: 0
    assert_select "th", text: "Email", count: 0
  end

  # ------------------------------------------------------------------- csv

  test "exports what the page shows" do
    shift(year: YEAR - 1, hours: 6)
    shift(year: YEAR, hours: 4)

    get teams_positions_special_teams_hours_path(report_params(show_signups: "1").merge(format: :csv))

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match "special-teams-hours-#{YEAR - 1}-#{YEAR}.csv", response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_equal "Callsign,Name,Status,Email,#{YEAR - 1} Hours,#{YEAR - 1} Sign-Ups," \
                 "#{YEAR} Hours,#{YEAR} Sign-Ups,Total Hours,Total Sign-Ups", lines.first
    assert_match(/\A#{Regexp.escape(@earner.callsign)},.*,6\.00,0,4\.00,0,10\.00,0\z/, lines.second)
    assert_equal 2, lines.size
  end

  # Follows the link the page draws rather than building one, so a request the
  # export link failed to carry would show up here.
  test "the page's export link carries the whole request" do
    shift
    PersonPosition.create!(person: @outsider, position: @green)

    get teams_positions_special_teams_hours_path(report_params(show_signups: "1", include_holders: "1"))
    get css_select("a[href*='.csv']").first["href"]

    assert_response :success
    lines = response.body.split("\n")
    assert_includes lines.first, "#{YEAR} Sign-Ups"
    assert(lines.any? { |line| line.start_with?("#{@outsider.callsign},") }, "the holder with no hours is exported")
  end

  test "the export leaves out name and email for a reader not allowed them" do
    shift
    sign_in_as(@event_manager)

    get teams_positions_special_teams_hours_path(report_params.merge(format: :csv))

    assert_equal "Callsign,Status,#{YEAR - 1} Hours,#{YEAR} Hours,Total Hours",
                 response.body.split("\n").first
  end

  test "an export with no report behind it returns to the page" do
    get teams_positions_special_teams_hours_path(format: :csv)

    assert_redirected_to teams_positions_special_teams_hours_path
  end

  test "an export that cannot run returns to the page with what was asked for" do
    get teams_positions_special_teams_hours_path(report: { start_year: YEAR - 1, end_year: YEAR, show_signups: "1" },
                                                 format: :csv)

    assert_redirected_to teams_positions_special_teams_hours_path(
      report: { start_year: YEAR - 1, end_year: YEAR, show_signups: "1" }
    )
  end
end
