# frozen_string_literal: true

require "test_helper"

class Quartermaster::PotentialSwagControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  # The fixtures hold five people in an active status, and this report lists
  # every one of them -- there is no service floor to keep anyone off.
  ROSTER_SIZE = 5

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @quartermaster = person(:echelon_ranger)
    @swag_editor = person(:auditor_ranger)
    @outsider = person(:plate_collision_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::QUARTERMASTER, "Quartermaster")
    ensure_role(Role::EDIT_SWAG, "Edit Swag")
    grant_role(@admin, Role::ADMIN)
    grant_role(@quartermaster, Role::QUARTERMASTER)
    grant_role(@swag_editor, Role::EDIT_SWAG)

    # See PotentialSwagReportTest for why both year columns are set directly.
    Person.update_all(years_as_ranger: nil, years_of_signups: [])

    # Every active-status fixture lands on the roster, so all five are given
    # service rather than left to arrive as incidental zero-year rows. The two
    # viewers who are not in an active status -- @quartermaster (echelon) and
    # @swag_editor (auditor) -- never appear, which is what lets the role tests
    # assert on an empty set of links.
    @candidate = person(:ranger_with_custom_gender) # CustomGender, active, 4y -> 5-year
    @veteran = person(:inactive_ranger)             # InactiveRanger, inactive, 9y -> 10-year
    @retired = person(:retired_ranger)              # RetiredRanger, retired, 4y -> 5-year
    @between = @admin                               # TestRanger, active, 2y -> no milestone
    @peer = @outsider                               # RANGER1, active, 2y -> no milestone

    @candidate.update!(years_as_ranger: [2022, 2023, 2024, 2025])
    @veteran.update!(years_as_ranger: (2017..2025).to_a)
    @retired.update!(years_as_ranger: [2019, 2020, 2021, 2022])
    @between.update!(years_as_ranger: [2024, 2025])
    @peer.update!(years_as_ranger: [2024, 2025])

    sign_up(@candidate)
    sign_up(@veteran)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "admin, quartermaster, and edit swag may all view the report" do
    [@admin, @quartermaster, @swag_editor].each do |viewer|
      sign_in_as(viewer)
      get quartermaster_potential_swag_path
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "denies access without the admin, quartermaster, or edit swag role" do
    sign_in_as(@outsider)
    get quartermaster_potential_swag_path
    assert_response :redirect
  end

  # Upstream has no filter at all, so arriving pre-filtered would be an
  # invention -- and the page draws no chip to admit one.
  test "arrives unfiltered, every active status on the roster" do
    get quartermaster_potential_swag_path
    assert_response :success

    assert_includes roster_callsigns, @retired.callsign
    assert_includes roster_callsigns, @veteran.callsign
    assert_select "a[aria-label^=?]", "Remove filter:", count: 0
  end

  test "people who hold no active status are never listed" do
    get quartermaster_potential_swag_path

    assert_not_includes roster_callsigns, person(:prospective_ranger).callsign
    assert_not_includes roster_callsigns, person(:bonked_ranger).callsign
  end

  test "the summary counts the same rows the roster shows" do
    get quartermaster_potential_swag_path
    assert_response :success

    assert_equal [["10-year service", "1", "1"], ["5-year service", "2", "1"]], milestone_rows
  end

  test "stats follow the status scope" do
    get quartermaster_potential_swag_path
    assert_match(/3\s*At a Milestone/, stats_text)
    assert_match(/2\s*Milestone and Signed Up/, stats_text)

    get quartermaster_potential_swag_path(status: Person::ACTIVE)
    assert_match(/1\s*At a Milestone/, stats_text, "the retired 5-year candidate is out of scope"
    )
    assert_match(/1\s*Milestone and Signed Up/, stats_text)
  end

  test "each filter narrows the roster" do
    [[{ milestone: "5" }, [@candidate, @retired]],
     [{ milestone: "10" }, [@veteran]],
     [{ status: Person::RETIRED }, [@retired]],
     [{ signed_up: "yes" }, [@candidate, @veteran]],
     [{ milestone: "5", signed_up: "yes" }, [@candidate]],
     [{ milestone: "5", signed_up: "no" }, [@retired]],
     [{ status: Person::RETIRED, signed_up: "yes" }, []]].each do |filters, expected|
      get quartermaster_potential_swag_path(**filters)

      assert_response :success
      assert_equal expected.map(&:callsign).sort, roster_callsigns.sort, filters.inspect
    end
  end

  # A value outside the lines on offer would render an empty roster with no way
  # to tell a typo from a real gap.
  test "a milestone no one in the scope reaches is dropped, not applied" do
    get quartermaster_potential_swag_path(milestone: "25")

    assert_response :success
    assert_equal ROSTER_SIZE, roster_callsigns.size
    assert_select "a[aria-label^=?]", "Remove filter: Service Swag", count: 0
  end

  test "a status no one on the roster holds is dropped, not applied" do
    get quartermaster_potential_swag_path(status: Person::ALPHA)

    assert_response :success
    assert_equal ROSTER_SIZE, roster_callsigns.size
    assert_select "a[aria-label^=?]", "Remove filter: Status", count: 0
  end

  test "an unrecognised signed-up value is not a filter" do
    get quartermaster_potential_swag_path(signed_up: "0")

    assert_response :success
    assert_equal ROSTER_SIZE, roster_callsigns.size
    assert_select "a[aria-label^=?]", "Remove filter: Signed Up", count: 0
  end

  # The milestone select navigates, so its counts have to promise the roster the
  # choice delivers -- @retired is a 5-year candidate who has not signed up.
  test "the milestone select counts what the choice will deliver" do
    get quartermaster_potential_swag_path(signed_up: "yes")

    assert_response :success
    assert_select "select#milestone option[value=?]", "5", text: "5-year service (1)"
    assert_select "select#milestone option[value=?]", "10", text: "10-year service (1)"
  end

  # The summary row is an order sheet line: its counts describe every candidate
  # at that milestone, so its link has to hand over exactly those people. It
  # drops the sign-up filter to do that rather than advertising one number and
  # delivering another.
  test "a summary row hands over the people it counts" do
    get quartermaster_potential_swag_path(signed_up: "yes")
    assert_response :success

    row = css_select("#potential-swag-milestones tbody tr")
          .find { |tr| tr.css("th").text.strip == "5-year service" }
    assert_equal "2", row.css("td").first.text.strip

    get row.css("th a").first["href"]
    assert_response :success
    assert_equal [@candidate, @retired].map(&:callsign).sort, roster_callsigns.sort
    assert_select "a[aria-label^=?]", "Remove filter: Signed Up", count: 0
  end

  # The status select narrows too, so its counts have to answer the same
  # question the milestone select's do -- not "how many hold this status" but
  # "how many would I get".
  test "the status select counts what the choice will deliver" do
    get quartermaster_potential_swag_path(milestone: "10")

    assert_response :success
    # Only @veteran is a 10-year candidate, and they are inactive.
    assert_select "select#status option[value=?]", Person::INACTIVE, text: "inactive (1)"
    assert_select "select#status option[value=?]", Person::ACTIVE, text: "active (0)"
    assert_select "select#status option[value=?]", Person::RETIRED, text: "retired (0)"
  end

  # Every filter's default is already the "all" sentinel, so dropping a param is
  # enough to clear it -- no always: treatment needed, unlike Events Rangered.
  test "clearing the filters drops them from the URL entirely" do
    get quartermaster_potential_swag_path(milestone: "5", signed_up: "yes")
    assert_response :success

    clear = css_select("a").find { |link| link.text.strip == "Clear All Filters" }
    assert_not_nil clear
    assert_not_includes clear["href"], "milestone"
    assert_not_includes clear["href"], "signed_up"

    get clear["href"]
    assert_equal ROSTER_SIZE, roster_callsigns.size
  end

  test "says so plainly when the filters match no one" do
    get quartermaster_potential_swag_path(status: Person::RETIRED, signed_up: "yes")

    assert_response :success
    assert_empty roster_callsigns
    assert_match "No one matched the current filters", response.body
  end

  # The milestone is validated against the lines the CURRENT status scope
  # offers, so narrowing status can retire the milestone filter under it: the
  # only 10-year candidate is inactive, and there is no 10-year line to pick
  # once the scope is Active. The filter is dropped rather than applied, and the
  # chip goes with it -- an empty roster under a chip no one can act on reads as
  # a bug, where a missing chip says the choice is no longer on offer.
  test "a milestone the status scope no longer offers is dropped with its chip" do
    get quartermaster_potential_swag_path(milestone: "10", status: Person::ACTIVE)

    assert_response :success
    assert_equal [@candidate, @between, @peer].map(&:callsign).sort, roster_callsigns.sort
    assert_select "a[aria-label^=?]", "Remove filter: Service Swag", count: 0
    assert_select "a[aria-label^=?]", "Remove filter: Status"
  end

  test "says so plainly when no one reaches a milestone" do
    Person.update_all(years_as_ranger: [2025])

    get quartermaster_potential_swag_path
    assert_response :success
    assert_match "No one in this scope reaches a five-year mark", response.body
  end

  test "CSV carries the filtered rows, upstream's columns, and the year in its name" do
    get quartermaster_potential_swag_path(format: :csv)
    assert_response :success
    assert_match "#{Current.year}-potential-swag.csv", response.headers["Content-Disposition"]

    rows = response.body.split("\n")
    assert_equal Quartermaster::PotentialSwagController.csv_header(Current.year).join(","),
                 rows.first
    assert_equal ROSTER_SIZE + 1, rows.size, "header plus every active-status person"

    candidate_row = rows.find { |row| row.start_with?("#{@candidate.callsign},") }
    assert_equal [@candidate.callsign, @candidate.status, "4", "2022", "2025", "Y",
                  "5-year service"], candidate_row.split(",")
  end

  test "the CSV export honours the filters" do
    get quartermaster_potential_swag_path(format: :csv, milestone: "5", signed_up: "no")

    assert_response :success
    rows = response.body.split("\n")
    assert_equal 2, rows.size, "header plus the retired 5-year candidate who has not signed up"
    assert rows.last.start_with?("#{@retired.callsign},")
  end

  # Quartermaster and Edit Swag may read this report but not the person pages,
  # so linking every callsign would hand them a roster of links that all bounce.
  test "callsigns link only for readers who may open a person page" do
    get quartermaster_potential_swag_path
    assert_select "#potential-swag-roster th[scope=row] a", minimum: 1

    [@quartermaster, @swag_editor].each do |viewer|
      sign_in_as(viewer)
      get quartermaster_potential_swag_path

      assert_response :success
      assert_not_empty roster_callsigns, "#{viewer.callsign} should still see the roster"
      assert_select "#potential-swag-roster th[scope=row] a", count: 0,
                    message: "#{viewer.callsign} cannot open /person/:id"
    end
  end

  # The sidebar is visible to the union of every item's roles, so someone who
  # can only read this page must not be shown links that would bounce them.
  test "an edit swag holder sees Potential Swag and Swag but not Events Rangered" do
    sign_in_as(@swag_editor)
    get quartermaster_potential_swag_path

    assert_select "a[href=?]", quartermaster_potential_swag_path
    assert_select "a[href=?]", quartermaster_swag_path
    assert_select "a[href=?]", quartermaster_events_rangered_path, count: 0
  end

  private

  def sign_up(person, year: Current.year)
    slot = Slot.create!(position: positions(:ood_position), max: 10, active: true,
                        begins: Time.zone.local(year, 8, 20, 9, 0, 0),
                        ends: Time.zone.local(year, 8, 20, 17, 0, 0))
    PersonSlot.create!(person:, slot:)
  end

  def roster_callsigns
    css_select("#potential-swag-roster th[scope=row]").map { |cell| cell.text.strip }
  end

  # [service swag, candidates, signed up] per line, largest milestone first.
  def milestone_rows
    css_select("#potential-swag-milestones tbody tr").map do |row|
      [row.css("th").text.strip, *row.css("td").map { |cell| cell.text.strip }]
    end
  end

  def stats_text
    css_select("div.flex.flex-row.flex-wrap").first&.text.to_s.squish
  end
end
