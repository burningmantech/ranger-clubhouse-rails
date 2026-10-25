# frozen_string_literal: true

require "test_helper"

class Quartermaster::AlphaShirtsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @mentor = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::QUARTERMASTER, "Quartermaster")
    ensure_role(Role::MENTOR, "Mentor")
    grant_role(@admin, Role::ADMIN)
    grant_role(@mentor, Role::MENTOR)

    @alpha = person(:alpha_ranger)
    @prospective = person(:prospective_ranger)

    @large = swag(:tshirt_large)
    @small = swag(:tshirt_small)
    @long_sleeve = swag(:longsleeve_medium)

    # The Alpha has every size; the Prospective is missing a backup, which is
    # what the Unknown bucket and the "Missing a size" stat are counting.
    @alpha.update!(tshirt_swag: @large, tshirt_secondary_swag: @large, long_sleeve_swag: @long_sleeve)
    @prospective.update!(tshirt_swag: @small, tshirt_secondary_swag: nil, long_sleeve_swag: @long_sleeve)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "admin, quartermaster, and mentor may all view the report" do
    quartermaster = @outsider
    grant_role(quartermaster, Role::QUARTERMASTER)

    [@admin, @mentor, quartermaster].each do |viewer|
      sign_in_as(viewer)
      get quartermaster_alpha_shirts_path
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "denies access without the admin, quartermaster, or mentor role" do
    sign_in_as(@outsider)
    get quartermaster_alpha_shirts_path
    assert_response :redirect
  end

  # The status filter is the whole report -- anyone else showing up would be
  # counted into an order for shirts they are not owed.
  test "lists only Alphas and Prospectives" do
    get quartermaster_alpha_shirts_path
    assert_response :success

    listed = listed_callsigns

    assert_includes listed, @alpha.callsign
    assert_includes listed, @prospective.callsign

    Person.where.not(status: [Person::ALPHA, Person::PROSPECTIVE]).pluck(:callsign).each do |callsign|
      assert_not_includes listed, callsign
    end
  end

  test "a person with no recorded size is counted, not dropped" do
    get quartermaster_alpha_shirts_path
    assert_response :success

    backups = assigns_kind("T-Shirt Backups")
    unknown = backups.sizes.find { |size| size.title == ShirtTotals::UNKNOWN }

    assert_not_nil unknown, "the missing backup size must land in the Unknown bucket"
    assert_equal 1, unknown.count
    assert_equal 2, backups.sizes.sum(&:count), "every person must appear in exactly one size"
  end

  # A size run printed alphabetically reads "L, M, S, XL, XS" -- useless for
  # counting boxes, and the regression this guards. Sizes are set with
  # update_columns so promoting a third person does not drag in the position
  # grants a real status change performs; this report only reads.
  test "sizes come back in size-run order with Unknown last" do
    @prospective.update_columns(tshirt_secondary_swag_id: @small.id)
    person(:bonked_ranger).update_columns(status: Person::ALPHA, tshirt_secondary_swag_id: nil)

    get quartermaster_alpha_shirts_path
    titles = assigns_kind("T-Shirt Backups").sizes.map(&:title)

    assert_equal [@small.title, @large.title, ShirtTotals::UNKNOWN], titles
  end

  test "roster CSV carries one row per person and the year in its name" do
    get quartermaster_alpha_shirts_path(format: :csv)
    assert_response :success
    assert_match "#{Current.year}-alpha-shirts.csv", response.headers["Content-Disposition"]

    rows = response.body.split("\n")
    assert_equal Quartermaster::AlphaShirtsController::ROSTER_HEADER.join(","), rows.first
    assert_equal 3, rows.size, "header plus the Alpha and the Prospective"
    assert_match ShirtTotals::UNKNOWN, rows.find { |row| row.start_with?(@prospective.callsign) }
  end

  test "counts CSV names its shirt kind on every row" do
    get quartermaster_alpha_shirts_counts_path
    assert_response :success
    assert_match "#{Current.year}-alpha-shirt-counts.csv", response.headers["Content-Disposition"]

    rows = response.body.split("\n")
    assert_equal Quartermaster::AlphaShirtsController::COUNTS_HEADER.join(","), rows.first
    assert rows.drop(1).all? { |row| ShirtTotals::KINDS.any? { |kind| row.start_with?(kind[:name]) } }
  end

  test "each filter narrows the roster" do
    [[{ status: Person::ALPHA }, [@alpha]],
     [{ status: Person::PROSPECTIVE }, [@prospective]],
     [{ tshirt: @small.title }, [@prospective]],
     [{ tshirt_secondary: ShirtTotals::UNKNOWN }, [@prospective]],
     [{ long_sleeve: @long_sleeve.title }, [@alpha, @prospective]],
     [{ missing: "1" }, [@prospective]],
     [{ status: Person::ALPHA, missing: "1" }, []]].each do |filters, expected|
      get quartermaster_alpha_shirts_path(**filters)

      assert_response :success
      assert_equal expected.map(&:callsign).sort, listed_callsigns.sort, filters.inspect
    end
  end

  # An unchecked box posts "0" and an untouched select posts "all"; neither is a
  # filter, so neither may draw a chip.
  test "the off values of every filter leave the roster whole" do
    get quartermaster_alpha_shirts_path(status: "all", tshirt: "all", tshirt_secondary: "all",
                                        long_sleeve: "all", missing: "0")

    assert_response :success
    assert_equal 2, listed_callsigns.size
    assert_select "a[aria-label^=?]", "Remove filter", count: 0
  end

  # Filtering to Unknown must not make the order sheet look like no one needs a
  # shirt, so the size runs, the stats, and both exports stay whole.
  test "filters narrow the roster but not the size runs or the exports" do
    get quartermaster_alpha_shirts_path(missing: "1")
    assert_response :success

    assert_equal 1, listed_callsigns.size
    assert_match(/Showing 1 of 2 people/, response.body.gsub(/\s+/, " "))
    # Both people still counted in the T-shirt run rendered on the page.
    assert_equal 2, assigns_kind("T-Shirts").sizes.sum(&:count)

    get quartermaster_alpha_shirts_path(format: :csv, missing: "1")
    assert_equal 3, response.body.split("\n").size, "the export is the whole report, not the view"
  end

  test "says so plainly when no one holds either status" do
    Person.where(status: [Person::ALPHA, Person::PROSPECTIVE]).update_all(status: Person::ACTIVE)

    get quartermaster_alpha_shirts_path
    assert_response :success
    assert_match "No one holds Prospective or Alpha status", response.body
  end

  # The sidebar is visible to the union of both items' roles, so a Mentor must
  # not be shown the Swag link they cannot open.
  test "a mentor sees Alpha Shirts in the sidebar but not Swag" do
    sign_in_as(@mentor)
    get quartermaster_alpha_shirts_path

    assert_select "a[href=?]", quartermaster_alpha_shirts_path
    assert_select "a[href=?]", quartermaster_swag_path, count: 0
  end

  private

  # The roster's first column. Size-run tables put their size there too, so the
  # callsigns are whatever is left once the run titles are dropped.
  def listed_callsigns
    run_titles = ShirtTotals.for_people(Person.where(status: [Person::ALPHA, Person::PROSPECTIVE]).to_a)
                            .flat_map { |kind| kind.sizes.map(&:title) }

    css_select("th[scope=row]").map { |cell| cell.text.strip } - run_titles
  end

  def assigns_kind(name)
    ShirtTotals.for_people(Person.where(status: [Person::ALPHA, Person::PROSPECTIVE])
                                 .includes(:tshirt_swag, :tshirt_secondary_swag, :long_sleeve_swag).to_a)
               .find { |kind| kind.name == name }
  end
end
