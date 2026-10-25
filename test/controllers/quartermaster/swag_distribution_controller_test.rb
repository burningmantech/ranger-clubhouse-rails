# frozen_string_literal: true

require "test_helper"

class Quartermaster::SwagDistributionControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  # The year the bulk of the test swag was issued in. A past year on purpose:
  # the page defaults to Current.year, so tests that pass ?year= prove the
  # scoping rather than riding the default.
  REPORT_YEAR = 2025

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @quartermaster = person(:echelon_ranger)
    @mentor = person(:auditor_ranger) # may see sibling Alpha Shirts, not this
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::QUARTERMASTER, "Quartermaster")
    ensure_role(Role::MENTOR, "Mentor")
    grant_role(@admin, Role::ADMIN)
    grant_role(@quartermaster, Role::QUARTERMASTER)
    grant_role(@mentor, Role::MENTOR)

    @shirts = person(:plate_collision_ranger)       # RANGER1
    @decorated = person(:active_ranger)             # TestRanger
    @dupe = person(:retired_ranger)                 # RetiredRanger
    @past = person(:ranger_with_custom_gender)      # CustomGender

    # insert_all, not create!: PersonSwag validates person+swag uniqueness, but
    # the production table holds real duplicates (the same shirt issued twice),
    # and the report must show both. notes is NOT NULL.
    PersonSwag.delete_all
    PersonSwag.insert_all(
      [
        # REPORT_YEAR: a plain two-shirt person...
        { person_id: @shirts.id, swag_id: swag(:tshirt_small).id, year_issued: REPORT_YEAR },
        { person_id: @shirts.id, swag_id: swag(:longsleeve_small).id, year_issued: REPORT_YEAR },
        # ...one item in every non-shirt category...
        { person_id: @decorated.id, swag_id: swag(:tshirt_medium).id, year_issued: REPORT_YEAR },
        { person_id: @decorated.id, swag_id: swag(:service_pin_5_year).id, year_issued: REPORT_YEAR },
        { person_id: @decorated.id, swag_id: swag(:toaster_pin).id, year_issued: REPORT_YEAR },
        { person_id: @decorated.id, swag_id: swag(:service_patch_5_year).id, year_issued: REPORT_YEAR },
        { person_id: @decorated.id, swag_id: swag(:org_patch_5_year).id, year_issued: REPORT_YEAR },
        { person_id: @decorated.id, swag_id: swag(:org_pin).id, year_issued: REPORT_YEAR },
        { person_id: @decorated.id, swag_id: swag(:other_swag).id, year_issued: REPORT_YEAR },
        # ...and the same shirt issued twice to one person.
        { person_id: @dupe.id, swag_id: swag(:tshirt_large).id, year_issued: REPORT_YEAR },
        { person_id: @dupe.id, swag_id: swag(:tshirt_large).id, year_issued: REPORT_YEAR },
        # Another year, and the current one, to prove the scoping.
        { person_id: @past.id, swag_id: swag(:longsleeve_medium).id, year_issued: REPORT_YEAR - 1 },
        { person_id: @shirts.id, swag_id: swag(:tshirt_small).id, year_issued: Current.year }
      ].map { |row| row.merge(notes: "") }
    )

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "admin and quartermaster may both view the report" do
    [@admin, @quartermaster].each do |viewer|
      sign_in_as(viewer)
      get quartermaster_swag_distribution_path
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  # Mentor is the realistic wrong-role probe: it opens the sibling Alpha
  # Shirts page, and must not leak in here.
  test "denies access without the admin or quartermaster role" do
    [@mentor, @outsider].each do |viewer|
      sign_in_as(viewer)
      get quartermaster_swag_distribution_path
      assert_response :redirect, "#{viewer.callsign} should be turned away"
    end
  end

  test "defaults to the current year" do
    get quartermaster_swag_distribution_path

    assert_response :success
    assert_equal [@shirts.callsign], roster_callsigns
  end

  test "a year narrows to the swag issued in it" do
    get quartermaster_swag_distribution_path(year: REPORT_YEAR)

    assert_response :success
    assert_equal [@shirts, @decorated, @dupe].map(&:callsign).sort, roster_callsigns.sort
    assert_not_includes roster_callsigns, @past.callsign
  end

  test "All covers every year on record" do
    get quartermaster_swag_distribution_path(year: "All")

    assert_response :success
    assert_equal [@shirts, @decorated, @dupe, @past].map(&:callsign).sort, roster_callsigns.sort
  end

  # A junk year must not read as a real scope -- the shared setup_year already
  # coerces it, and "all" (lowercase) is not the All the selector offers.
  test "an unrecognised year falls back to the current year" do
    ["1990", "banana", "all"].each do |year|
      get quartermaster_swag_distribution_path(year:)

      assert_response :success
      assert_equal [@shirts.callsign], roster_callsigns, "year=#{year}"
    end
  end

  test "rows come back callsign ascending, case-insensitively" do
    get quartermaster_swag_distribution_path(year: "All")

    # customgender < ranger1 < retiredranger < testranger
    assert_equal [@past, @shirts, @dupe, @decorated].map(&:callsign), roster_callsigns
  end

  # hero_panel drops year_options' own inject-the-requested-year guard, so the
  # controller has to put @year in the list itself. Without it the dropdown
  # showed the current year while the body reported the year that was asked for.
  test "the year selector shows the requested year even when it holds no swag" do
    get quartermaster_swag_distribution_path(year: "2010")

    assert_response :success
    assert_select "select#year-selector-compact option[value=?][selected=selected]", "2010"
  end

  # The selector must not offer a year setup_year will refuse: picking it would
  # silently render the current year's roster instead.
  test "years outside the accepted window are not offered" do
    PersonSwag.insert_all([{ person_id: @past.id, swag_id: swag(:tshirt_small).id,
                             year_issued: 2205, notes: "" },
                           { person_id: @past.id, swag_id: swag(:tshirt_medium).id,
                             year_issued: 2008, notes: "" }])

    get quartermaster_swag_distribution_path
    assert_response :success
    assert_select "select#year-selector-compact option[value=?]", "2205", count: 0
    assert_select "select#year-selector-compact option[value=?]", "2008", count: 0
  end

  # An item with no year was never attributed to an event. Counting it under All
  # while no per-year view can reach it would stop the years from summing.
  test "rows with no year issued are left out of the All view" do
    PersonSwag.insert_all([{ person_id: @past.id, swag_id: swag(:org_pin).id,
                             year_issued: nil, notes: "" }])

    get quartermaster_swag_distribution_path(year: "All")
    assert_response :success
    assert_not_includes item_lines, "Org Pin: Org 5 Year Service Pin"
  end

  # Under All the same shirt issued at two events is otherwise byte-identical to
  # one issued twice at a single event.
  test "the All view stamps each item with the year it was issued" do
    get quartermaster_swag_distribution_path(year: "All")

    assert_response :success
    assert_includes item_lines, "Long Sleeve Shirt: Ranger Long Sleeve M (#{REPORT_YEAR - 1})"
    assert_includes item_lines, "T-Shirt: Ranger T-Shirt S (#{Current.year})"
    # A single year needs no stamp -- every row on the page shares it.
    get quartermaster_swag_distribution_path(year: REPORT_YEAR)
    assert_includes item_lines, "T-Shirt: Ranger T-Shirt S"
  end

  # person_swag has no database foreign keys and the upstream Laravel app writes
  # the same table, so a row can outlive its swag or its person.
  test "an orphaned row does not take the whole report down" do
    PersonSwag.insert_all([{ person_id: @past.id, swag_id: 999_999, year_issued: REPORT_YEAR,
                             notes: "" },
                           { person_id: 999_999, swag_id: swag(:tshirt_small).id,
                             year_issued: REPORT_YEAR, notes: "" }])

    get quartermaster_swag_distribution_path(year: REPORT_YEAR)
    assert_response :success
    # The missing swag is named rather than rendered blank; the row whose person
    # is gone has nothing to render and is left out.
    assert_includes item_lines, "Other: unknown swag 999999"
    assert_equal [@shirts, @decorated, @dupe, @past].map(&:callsign).sort, roster_callsigns.sort

    get quartermaster_swag_distribution_path(year: REPORT_YEAR, format: :csv)
    assert_response :success
  end

  # Each line reads "Category: Title". Org pins get their own label -- upstream
  # dumped the whole org-pin type in Other.
  test "every item renders on its own labelled line, org pins under their own category" do
    get quartermaster_swag_distribution_path(year: REPORT_YEAR)
    assert_response :success

    { "T-Shirt" => "Ranger T-Shirt M",
      "Service Pin" => "Ranger 5 Year Service Pin",
      "Toaster Pin" => "Toaster Pin",
      "Service Patch" => "5 Year Service Patch",
      "Org Patch" => "5 Year B.M. Service Patch",
      "Org Pin" => "Org 5 Year Service Pin",
      "Other" => "Commemorative Mug" }.each do |label, title|
      assert_includes item_lines, "#{label}: #{title}"
    end
    assert_not_includes item_lines, "Other: Org 5 Year Service Pin"
  end

  test "the same swag issued twice renders twice and counts twice" do
    get quartermaster_swag_distribution_path(year: REPORT_YEAR)
    assert_response :success

    assert_equal 2, item_lines.count("T-Shirt: Ranger T-Shirt L")

    dupe_row = css_select("#swag-distribution-roster tbody tr")
               .find { |row| row.css("th").text.strip == @dupe.callsign }
    assert_equal "2", dupe_row.css("td").first.text.strip
  end

  test "stats count items per category from the same rows the roster shows" do
    get quartermaster_swag_distribution_path(year: REPORT_YEAR)

    assert_match(/3\s*People/, stats_text)
    assert_match(/11\s*Items/, stats_text)
    assert_match(/4\s*T-Shirts/, stats_text)
    assert_match(/1\s*Org Pins/, stats_text)

    # The current year holds a single t-shirt, so every other category is
    # absent and must not draw a box.
    get quartermaster_swag_distribution_path
    assert_match(/1\s*T-Shirts/, stats_text)
    assert_no_match(/Org Pins/, stats_text)
    assert_no_match(/Long Sleeve Shirts/, stats_text)
  end

  # A category narrows to the people who received one; their row still lists
  # everything they got.
  test "the category filter narrows to its recipients, keeping their full rows" do
    get quartermaster_swag_distribution_path(year: REPORT_YEAR, category: "org_pins")

    assert_response :success
    assert_equal [@decorated.callsign], roster_callsigns
    assert_includes item_lines, "T-Shirt: Ranger T-Shirt M"
  end

  # The controller keeps a zero-count category filter on purpose, and the year
  # selector carries it across a year change. If the select dropped its option,
  # it read "All" while the chip said otherwise -- and Apply, which posts every
  # control touched or not, silently widened the scope.
  test "a filtered category with no items still appears in the select" do
    get quartermaster_swag_distribution_path(year: Current.year, category: "org_pins")

    assert_response :success
    assert_equal 0, @controller.view_assigns["category_counts"][:org_pins]
    assert_select "select#category option[value=?][selected=selected]", "org_pins"
    assert_select "select#category option[value=?]", "org_pins", text: "Org Pins (0)"
  end

  # The filter bar itself only renders when there are rows to narrow, so a year
  # with no swag at all needs its own way to show and drop a carried filter.
  test "a year with no swag still shows and can clear a carried filter" do
    get quartermaster_swag_distribution_path(year: "2010", category: "org_pins")

    assert_response :success
    assert_match "No swag was handed out in 2010", response.body
    chip = css_select("a[aria-label^='Remove filter: Category']").first
    assert_not_nil chip, "the carried filter must stay removable"
    assert_includes chip["href"], "year=2010"
  end

  test "an unrecognised category falls back to all, not to an empty roster" do
    get quartermaster_swag_distribution_path(year: REPORT_YEAR, category: "belt_buckles")

    assert_response :success
    assert_equal 3, roster_callsigns.size
    assert_select "a[aria-label^=?]", "Remove filter: Category", count: 0
  end

  # The page's default is the current year, not an "off" state, so every URL it
  # builds must say the year out loud or a chip removal would jump the reader
  # back to the current event.
  test "chip and clear URLs carry the year" do
    get quartermaster_swag_distribution_path(year: REPORT_YEAR, category: "tshirts")
    assert_response :success

    chip = css_select("a[aria-label^='Remove filter: Category']").first
    assert_not_nil chip, "an active category must draw a chip"
    assert_includes chip["href"], "year=#{REPORT_YEAR}"

    clear = css_select("a").find { |link| link.text.strip == "Clear All Filters" }
    assert_not_nil clear
    assert_includes clear["href"], "year=#{REPORT_YEAR}"
  end

  test "says so plainly when a year has no swag on record" do
    get quartermaster_swag_distribution_path(year: "2010")

    assert_response :success
    assert_match "No swag was handed out in 2010", response.body
  end

  test "CSV carries one row per person with newline-joined category cells" do
    get quartermaster_swag_distribution_path(year: REPORT_YEAR, format: :csv)
    assert_response :success
    assert_match "#{REPORT_YEAR}-swag-distribution.csv", response.headers["Content-Disposition"]

    header = response.body.lines.first.chomp
    assert_equal "Callsign,T-Shirts,Long Sleeve Shirts,Toaster Pins,Service Pins," \
                 "Service Patches,Org Patches,Org Pins,Other", header

    # A multi-item cell is newline-joined inside one quoted cell -- the same
    # shirt twice stays two lines.
    assert_includes response.body,
                    %(#{@dupe.callsign},"Ranger T-Shirt L\nRanger T-Shirt L",-,-,-,-,-,-,-)
    # The two-shirt person: empty categories are dashes, matching upstream.
    assert_includes response.body,
                    "#{@shirts.callsign},Ranger T-Shirt S,Ranger Long Sleeve S,-,-,-,-,-,-"
    # The org pin writes to its own column, leaving Other to the mug.
    assert_includes response.body, "Org 5 Year Service Pin,Commemorative Mug"
  end

  test "the CSV export honours the category filter and All names its file" do
    get quartermaster_swag_distribution_path(year: REPORT_YEAR, category: "org_pins",
                                             format: :csv)
    assert_response :success
    assert_equal 2, response.body.split("\n").size, "header plus the one org-pin recipient"

    get quartermaster_swag_distribution_path(year: "All", format: :csv)
    assert_response :success
    assert_match "all-swag-distribution.csv", response.headers["Content-Disposition"]
    # One row per person; embedded cell newlines make a raw line count lie, so
    # count the row starts instead.
    [@shirts, @decorated, @dupe, @past].each do |recipient|
      assert_match(/^#{recipient.callsign},/, response.body)
    end
  end

  # Quartermasters may read this page but not the person pages it would link
  # to, so they get plain callsigns rather than links that bounce.
  test "callsigns link only for readers who may open a person page" do
    get quartermaster_swag_distribution_path(year: REPORT_YEAR)
    assert_select "#swag-distribution-roster th[scope=row] a", minimum: 1

    sign_in_as(@quartermaster)
    get quartermaster_swag_distribution_path(year: REPORT_YEAR)
    assert_response :success
    assert_not_empty roster_callsigns
    assert_select "#swag-distribution-roster th[scope=row] a", count: 0
  end

  test "a mentor sees Alpha Shirts in the sidebar but not Swag Distribution" do
    sign_in_as(@mentor)
    get quartermaster_alpha_shirts_path

    assert_response :success
    assert_select "a[href=?]", quartermaster_alpha_shirts_path
    assert_select "a[href*=?]", "swag-distribution", count: 0
  end

  private

  def roster_callsigns
    css_select("#swag-distribution-roster th[scope=row]").map { |cell| cell.text.strip }
  end

  # Every "Category: Title" line in the roster, squished so the label span and
  # the title text read as one string.
  def item_lines
    css_select("#swag-distribution-roster td div").map { |line| line.text.squish }
  end

  def stats_text
    css_select("div.flex.flex-row.flex-wrap").first&.text.to_s.squish
  end
end
