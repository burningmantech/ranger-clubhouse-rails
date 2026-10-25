# frozen_string_literal: true

require "test_helper"

class Quartermaster::EventsRangeredControllerTest < ActionDispatch::IntegrationTest
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

    # The census reads every Person, so the fixtures are cleared and only the
    # subjects given service. Both columns are set directly: creating Timesheet
    # or PersonSlot rows would fire YearsManagement, which recomputes them and
    # applies the six-hour rule that would silently drop these years.
    # years_as_ranger is nullable; years_of_signups is NOT NULL, so it is
    # cleared to an empty array rather than to nil. Pass the Array, not the
    # string "[]" -- update_all runs the value through the column's JSON coder,
    # so a string is stored double-encoded and reads back as the String "[]".
    Person.update_all(years_as_ranger: nil, years_of_signups: [])

    @long = person(:active_ranger)          # TestRanger, active
    @peer = person(:plate_collision_ranger) # RANGER1, active
    @short = person(:ranger_with_custom_gender) # CustomGender, active
    @retired = person(:retired_ranger)      # RetiredRanger, retired
    @never = person(:prospective_ranger)    # no service at all

    @long.update!(years_as_ranger: [2015, 2016, 2017], years_of_signups: [Current.year])
    @peer.update!(years_as_ranger: [2015, 2016, 2017], years_of_signups: [Current.year - 1])
    @short.update!(years_as_ranger: [2024], years_of_signups: [])
    @retired.update!(years_as_ranger: [2001, 2002, 2003, 2004, 2005], years_of_signups: [])

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "admin, quartermaster, and timesheet management may all view the census" do
    [@admin, @quartermaster, @timesheet_manager].each do |viewer|
      sign_in_as(viewer)
      get quartermaster_events_rangered_path
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "denies access without the admin, quartermaster, or timesheet management role" do
    sign_in_as(@outsider)
    get quartermaster_events_rangered_path
    assert_response :redirect
  end

  # A person with no rangered years has no service to report, and upstream's
  # query cannot produce a zero-years row either.
  test "people who have never rangered are not listed" do
    get quartermaster_events_rangered_path(status: "all")
    assert_response :success

    assert_not_includes roster_callsigns, @never.callsign
    assert_equal [@retired, @long, @peer, @short].map(&:callsign).sort, roster_callsigns.sort
  end

  test "defaults to Active accounts" do
    get quartermaster_events_rangered_path
    assert_response :success

    assert_equal [@long, @peer, @short].map(&:callsign).sort, roster_callsigns.sort
    assert_not_includes roster_callsigns, @retired.callsign
  end

  # Longest service first, then callsign -- case-insensitively, so RANGER1 sorts
  # against TestRanger by letter and not by ASCII.
  test "rows come back longest service first, then by callsign" do
    get quartermaster_events_rangered_path

    assert_equal [@peer.callsign, @long.callsign, @short.callsign], roster_callsigns
  end

  test "the distribution counts the same rows the roster shows" do
    get quartermaster_events_rangered_path
    assert_response :success

    assert_equal [["3 years", "2", "1"], ["1 year", "1", "0"]], distribution_rows
  end

  # The stats describe the status scope, so clearing the status filter has to
  # move them.
  test "stats follow the status scope" do
    get quartermaster_events_rangered_path
    assert_match(/3\s*People/, stats_text)
    assert_match(/1\s*Signed Up for #{Current.year}/, stats_text)
    assert_match(/2\s*Not signed up/, stats_text)
    assert_match(/3 years\s*Longest Service/, stats_text)

    get quartermaster_events_rangered_path(status: "all")
    assert_match(/4\s*People/, stats_text)
    assert_match(/5 years\s*Longest Service/, stats_text)
  end

  test "each filter narrows the roster" do
    [[{}, [@peer, @long, @short]],
     [{ status: "all" }, [@retired, @peer, @long, @short]],
     [{ status: Person::RETIRED }, [@retired]],
     [{ years: "3" }, [@peer, @long]],
     [{ signed_up: "yes" }, [@long]],
     [{ signed_up: "no" }, [@peer, @short]],
     [{ years: "3", signed_up: "yes" }, [@long]],
     [{ years: "1", signed_up: "yes" }, []]].each do |filters, expected|
      get quartermaster_events_rangered_path(**filters)

      assert_response :success
      assert_equal expected.map(&:callsign).sort, roster_callsigns.sort, filters.inspect
    end
  end

  # The years select only offers buckets the status scope holds. A value outside
  # them would render an empty roster with no way to tell a typo from a real gap.
  test "a years value outside the buckets on offer is dropped, not applied" do
    get quartermaster_events_rangered_path(years: "17")

    assert_response :success
    assert_equal 3, roster_callsigns.size
    assert_select "a[aria-label^=?]", "Remove filter: Service", count: 0
  end

  # Falling back to "all" would answer a narrowing request with the whole
  # census, and because "all" draws no chip the page would not admit it.
  test "a status no one in the census holds falls back to Active, not to all" do
    get quartermaster_events_rangered_path(status: Person::ALPHA)

    assert_response :success
    assert_equal [@long, @peer, @short].map(&:callsign).sort, roster_callsigns.sort
    assert_not_includes roster_callsigns, @retired.callsign
    assert_select "a[aria-label^=?]", "Remove filter: Status"
  end

  # The years select navigates, so its counts have to promise the roster the
  # choice delivers -- @peer has 3 years but has not signed up.
  test "the years select counts what the choice will deliver" do
    get quartermaster_events_rangered_path(signed_up: "yes")

    assert_response :success
    assert_select "select#years option[value=?]", "3", text: "3 years (1)"
    # The band is still offered even though no one in it matches.
    assert_select "select#years option[value=?]", "1", text: "1 year (0)"
  end

  test "an unrecognised signed-up value is not a filter" do
    get quartermaster_events_rangered_path(signed_up: "0")

    assert_response :success
    assert_equal 3, roster_callsigns.size
    assert_select "a[aria-label^=?]", "Remove filter: Signed Up", count: 0
  end

  # An absent status param means Active, so the chip that removes the status
  # filter -- and Clear all -- have to say "all" out loud or they do nothing.
  test "removing the status filter says all out loud" do
    get quartermaster_events_rangered_path(years: "3")
    assert_response :success

    status_chip = css_select("a[aria-label^='Remove filter: Status']").first
    assert_not_nil status_chip, "the default Active scope must draw a chip"
    assert_includes status_chip["href"], "status=all"

    clear = css_select("a").find { |link| link.text.strip == "Clear All Filters" }
    assert_not_nil clear
    assert_includes clear["href"], "status=all"

    get clear["href"]
    assert_equal 4, roster_callsigns.size, "clearing must widen past Active"
  end

  test "says so plainly when the filters match no one" do
    get quartermaster_events_rangered_path(years: "1", signed_up: "yes")

    assert_response :success
    assert_empty roster_callsigns
    assert_match "No one matched the current filters", response.body
  end

  test "says so plainly when no one has rangered at all" do
    Person.update_all(years_as_ranger: nil)

    get quartermaster_events_rangered_path
    assert_response :success
    assert_match "No one has rangered a year yet", response.body
  end

  test "CSV carries the filtered rows, last name first, and the year in its name" do
    get quartermaster_events_rangered_path(format: :csv)
    assert_response :success
    assert_match "#{Current.year}-events-rangered.csv", response.headers["Content-Disposition"]

    rows = response.body.split("\n")
    assert_equal Quartermaster::EventsRangeredController.csv_header(Current.year).join(","),
                 rows.first
    assert_equal 4, rows.size, "header plus the three Active people"

    last_names = rows.drop(1).map { |row| row.split(",")[1] }
    assert_equal last_names.sort_by(&:downcase), last_names

    long_row = rows.find { |row| row.start_with?("#{@long.callsign},") }
    assert_equal [@long.callsign, @long.last_name, @long.desired_first_name, @long.status,
                  "3", "2015", "2017", "Y"], long_row.split(",")
  end

  test "the CSV export honours the filters, unlike the Alpha Shirts order sheet" do
    get quartermaster_events_rangered_path(format: :csv, signed_up: "yes")

    assert_response :success
    assert_equal 2, response.body.split("\n").size, "header plus the one person signed up"
  end

  # Quartermaster and Timesheet Management may read this census but not the
  # person pages, so linking every callsign would hand them a roster of links
  # that all bounce to /me.
  test "callsigns link only for readers who may open a person page" do
    get quartermaster_events_rangered_path
    assert_select "#events-rangered-roster th[scope=row] a", minimum: 1

    [@quartermaster, @timesheet_manager].each do |viewer|
      sign_in_as(viewer)
      get quartermaster_events_rangered_path

      assert_response :success
      assert_not_empty roster_callsigns, "#{viewer.callsign} should still see the roster"
      assert_select "#events-rangered-roster th[scope=row] a", count: 0,
                    message: "#{viewer.callsign} cannot open /person/:id, so must get plain callsigns"
    end
  end

  # The sidebar is visible to the union of every item's roles, so someone who
  # can only read this page must not be shown links that would bounce them.
  test "a timesheet manager sees Events Rangered in the sidebar but not Swag" do
    sign_in_as(@timesheet_manager)
    get quartermaster_events_rangered_path

    assert_select "a[href=?]", quartermaster_events_rangered_path
    assert_select "a[href=?]", quartermaster_swag_path, count: 0
  end

  private

  def roster_callsigns
    css_select("#events-rangered-roster th[scope=row]").map { |cell| cell.text.strip }
  end

  # [years label, people, signed up] per bucket, longest service first.
  def distribution_rows
    css_select("#events-rangered-distribution tbody tr").map do |row|
      [row.css("th").text.strip, *row.css("td")[0..0].map { |cell| cell.text.strip },
       row.css("td").last.text.strip]
    end
  end

  def stats_text
    css_select("div.flex.flex-row.flex-wrap").first&.text.to_s.squish
  end
end
