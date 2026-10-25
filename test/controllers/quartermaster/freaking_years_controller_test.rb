# frozen_string_literal: true

require "test_helper"

class Quartermaster::FreakingYearsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @quartermaster = person(:echelon_ranger)
    @timesheet_manager = person(:auditor_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::QUARTERMASTER, "Quartermaster")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")
    grant_role(@admin, Role::ADMIN)
    grant_role(@quartermaster, Role::QUARTERMASTER)
    grant_role(@timesheet_manager, Role::TIMESHEET_MANAGEMENT)

    # The report reads every Active person, so the column is cleared and the
    # subjects given service directly: creating Timesheet or PersonAward rows
    # would fire YearsManagement, which recomputes it. years_of_service is NOT
    # NULL, so it is cleared to an empty array -- the Array, not the string
    # "[]", which update_all would run through the JSON coder and store
    # double-encoded.
    Person.update_all(years_of_service: [])

    @long = person(:active_ranger)            # TestRanger, active
    @peer = person(:plate_collision_ranger)   # RANGER1, active
    @mid = person(:bonked_ranger)             # BonkedTest, made active below
    @newbie = person(:ranger_with_custom_gender) # CustomGender, active, no service
    @retired = person(:retired_ranger)        # RetiredRanger, retired

    # Ten and nine years, not three and one: a group list sorted as strings
    # would put "9" ahead of "10".
    @long.update!(years_of_service: (2010..2019).to_a)
    @peer.update!(years_of_service: [*2005..2013, 2022])
    # The only other Active fixtures are the three above.
    @mid.update_columns(status: Person::ACTIVE)
    @mid.update!(years_of_service: (2015..2023).to_a)
    @retired.update!(years_of_service: (2001..2012).to_a)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "admin and quartermaster may view both levels and both exports" do
    [@admin, @quartermaster].each do |viewer|
      sign_in_as(viewer)

      report_paths.each do |path|
        get path
        assert_response :success, "#{viewer.callsign} should be allowed into #{path}"
      end
    end
  end

  # Timesheet Management reads Events Rangered next door, but that grant was
  # TimesheetPolicy's. Upstream gates this report on AwardPolicy, which has none.
  test "denies timesheet management and anyone without a role" do
    [@timesheet_manager, @outsider].each do |viewer|
      sign_in_as(viewer)

      report_paths.each do |path|
        get path
        assert_response :redirect, "#{viewer.callsign} should be turned away from #{path}"
      end
    end
  end

  test "the index lists every group, longest service first, each drilling down to its page" do
    get quartermaster_freaking_years_path
    assert_response :success

    assert_equal ["10 Years • 2 people", "9 Years • 1 person", "0 Years • 1 person"], group_rows
    assert_match "Showing 4 people in 3 groups", response.body.squish

    [10, 9, 0].each do |years|
      assert_select "a[href=?]", quartermaster_freaking_years_group_path(years)
    end
  end

  # Upstream is Active only. The retired person has the longest service in the
  # fixtures, so a leak would show up as a group of its own. The exports read
  # the same rows, and their row counts are pinned below.
  test "only Active people are counted" do
    get quartermaster_freaking_years_path

    assert_select "a[href=?]", quartermaster_freaking_years_group_path(12), count: 0
  end

  test "says so plainly when there is no one Active" do
    Person.where(status: Person::ACTIVE).update_all(status: Person::INACTIVE)
    # The viewer's own status just changed with everyone else's.
    sign_in_as(@quartermaster)

    get quartermaster_freaking_years_path
    assert_response :success
    assert_match "There are no Active Rangers to report on.", response.body
    assert_select "a[href=?]", quartermaster_freaking_years_path(format: :csv), count: 0
  end

  # Callsign order is case-insensitive, so RANGER1 sorts against TestRanger by
  # letter and not by ASCII. Upstream's tiebreak never fired; this is the fix.
  test "a group page lists only that group, by callsign" do
    get quartermaster_freaking_years_group_path(10)
    assert_response :success

    assert_equal [@peer.callsign, @long.callsign], roster_callsigns
    assert_equal ["Plate Collision", "2005", "2022"], roster_cells(@peer)
    assert_select "h1", text: "10 Freaking Years"
  end

  # The group is the page and everyone on it is Active, so neither is a column.
  test "a group page has no years or status column" do
    get quartermaster_freaking_years_group_path(10)

    assert_equal ["Callsign", "Name", "First Year", "Last Year"],
                 css_select("#freaking-years-roster thead th").map { |th| th.text.strip }
  end

  test "a group page links back to the index" do
    get quartermaster_freaking_years_group_path(9)

    assert_select "a[aria-label=?][href=?]", "Back to Freaking Years", quartermaster_freaking_years_path
  end

  # Kept on purpose, as upstream keeps them: the total is the whole Active
  # roster. The name is the preferred one, as Person#desired_first_name has it.
  test "people with no service years yet have a group of their own" do
    get quartermaster_freaking_years_group_path(0)
    assert_response :success

    assert_equal [@newbie.callsign], roster_callsigns
    assert_equal ["#{@newbie.desired_first_name} #{@newbie.last_name}", "—", "—"], roster_cells(@newbie)
  end

  # Reachable from any bookmark: a group empties out the moment its last person
  # earns another year.
  test "a group no one holds goes back to the index and says why" do
    get quartermaster_freaking_years_group_path(3)

    assert_redirected_to quartermaster_freaking_years_path
    assert_equal "No Active Ranger has 3 service years.", flash[:error]

    get quartermaster_freaking_years_group_path(3, format: :csv)
    assert_redirected_to quartermaster_freaking_years_path
  end

  test "the all-groups CSV carries everyone, last name first, under upstream's columns" do
    get quartermaster_freaking_years_path(format: :csv)
    assert_response :success
    assert_match "#{Current.year}-freaking-years.csv", response.headers["Content-Disposition"]

    rows = response.body.split("\n")
    assert_equal Quartermaster::FreakingYearsController::CSV_HEADER.join(","), rows.first
    assert_equal 5, rows.size, "header plus the four Active people"

    last_names = rows.drop(1).map { |row| row.split(",")[1] }
    assert_equal last_names.sort_by(&:downcase), last_names

    assert_includes rows, [@peer.callsign, @peer.last_name, @peer.desired_first_name,
                           10, 2005, 2022].join(",")
  end

  # Blank rather than upstream's "n/a", so both year columns stay numeric.
  test "someone with no service years has blank year cells in the CSV" do
    get quartermaster_freaking_years_path(format: :csv)

    assert_includes response.body.split("\n"),
                    "#{@newbie.callsign},#{@newbie.last_name},#{@newbie.desired_first_name},0,,"
  end

  test "a group's CSV carries only that group and says which in its name" do
    get quartermaster_freaking_years_group_path(10, format: :csv)
    assert_response :success
    assert_match "#{Current.year}-freaking-years-10.csv", response.headers["Content-Disposition"]

    rows = response.body.split("\n")
    assert_equal Quartermaster::FreakingYearsController::CSV_HEADER.join(","), rows.first
    assert_equal [@peer.callsign, @long.callsign], rows.drop(1).map { |row| row.split(",").first }
  end

  test "each level offers its own export" do
    get quartermaster_freaking_years_path
    assert_select "a[href=?]", quartermaster_freaking_years_path(format: :csv), text: /Export All to CSV/

    get quartermaster_freaking_years_group_path(10)
    assert_select "a[href=?]", quartermaster_freaking_years_group_path(10, format: :csv), text: /Export CSV/
  end

  # A Quartermaster may read this report but not the person pages, so linking
  # every callsign would hand them a roster of links that all bounce to /me.
  test "callsigns link only for readers who may open a person page" do
    get quartermaster_freaking_years_group_path(10)
    assert_select "#freaking-years-roster th[scope=row] a", count: 2

    sign_in_as(@quartermaster)
    get quartermaster_freaking_years_group_path(10)

    assert_response :success
    assert_equal [@peer.callsign, @long.callsign], roster_callsigns
    assert_select "#freaking-years-roster th[scope=row] a", count: 0
  end

  # The sidebar is visible to the union of every item's roles, so each item has
  # to carry the gate its own controller enforces.
  test "a quartermaster sees Freaking Years in the sidebar" do
    sign_in_as(@quartermaster)
    get quartermaster_freaking_years_path

    assert_select "a[href=?]", quartermaster_freaking_years_path
  end

  test "a timesheet manager is not offered a link that would bounce them" do
    sign_in_as(@timesheet_manager)
    get quartermaster_events_rangered_path

    assert_response :success
    assert_select "a[href=?]", quartermaster_freaking_years_path, count: 0
  end

  private

  # Both levels and both exports: one gate covers all four.
  def report_paths
    [quartermaster_freaking_years_path, quartermaster_freaking_years_group_path(10),
     quartermaster_freaking_years_path(format: :csv),
     quartermaster_freaking_years_group_path(10, format: :csv)]
  end

  # "10 Years • 2 people" per drill-down row, in page order.
  def group_rows
    css_select("a[href^='#{quartermaster_freaking_years_path}/']").map { |row| row.text.squish }
  end

  def roster_callsigns
    css_select("#freaking-years-roster th[scope=row]").map { |cell| cell.text.strip }
  end

  # [name, first year, last year] for one person's row.
  def roster_cells(person)
    row = css_select("#freaking-years-roster tbody tr").find do |tr|
      tr.css("th[scope=row]").text.strip == person.callsign
    end

    row.css("td").map { |cell| cell.text.strip }
  end
end
