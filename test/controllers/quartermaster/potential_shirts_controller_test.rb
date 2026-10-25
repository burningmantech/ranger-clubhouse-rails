# frozen_string_literal: true

require "test_helper"

class Quartermaster::PotentialShirtsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  # A past year the report can be asked about (the controller's floor is
  # 2010), clear of the fixtures' 2023/2024 timesheets.
  YEAR = 2019

  # The thresholds under test: 18 hours earns a t-shirt, 40 a long sleeve.
  SS_HOURS = 18
  LS_HOURS = 40

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @quartermaster = person(:echelon_ranger)
    @outsider = person(:bonked_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::QUARTERMASTER, "Quartermaster")
    grant_role(@admin, Role::ADMIN)
    grant_role(@quartermaster, Role::QUARTERMASTER)

    Setting.create!(name: Setting::SHIRT_SHORT_SLEEVE_HOURS_THRESHOLD, value: SS_HOURS.to_s)
    Setting.create!(name: Setting::SHIRT_LONG_SLEEVE_HOURS_THRESHOLD, value: LS_HOURS.to_s)

    @position = positions(:ood_position) # count_hours: true
    Position.create!(id: Position::ALPHA, title: "Alpha")

    # Four would-be candidates:
    #   earner   -- 45 rangered hours, past both thresholds, full sizes
    #   partial  -- 20 rangered hours, t-shirt only
    #   pending  -- sign-up only, no rangered hours, no sizes recorded
    #   alpha    -- hours AND an Alpha shift, so excluded entirely
    @earner = @admin
    @partial = person(:retired_ranger)
    @pending = person(:ranger_with_custom_gender)
    @alpha_shifter = person(:inactive_ranger)

    @large = swag(:tshirt_large)
    @long_sleeve = swag(:longsleeve_medium)
    @earner.update!(tshirt_swag: @large, tshirt_secondary_swag: @large, long_sleeve_swag: @long_sleeve)
    @partial.update!(tshirt_swag: @large, tshirt_secondary_swag: nil, long_sleeve_swag: nil)

    ranger_hours(@earner, 45)
    ranger_hours(@partial, 20)
    ranger_hours(@alpha_shifter, 30)
    Timesheet.create!(person: @alpha_shifter, position_id: Position::ALPHA,
                      on_duty: Time.zone.local(YEAR, 8, 25, 18, 0, 0),
                      off_duty: Time.zone.local(YEAR, 8, 25, 20, 0, 0),
                      additional_notes: "alpha shift")

    slot = Slot.create!(position: @position, max: 10, active: true,
                        begins: Time.zone.local(YEAR, 8, 28, 9, 0, 0),
                        ends: Time.zone.local(YEAR, 8, 28, 15, 0, 0))
    PersonSlot.create!(person: @pending, slot:)

    # A still-open entry must not count as rangered hours -- and must not
    # crash the report with a NULL sum.
    Timesheet.create!(person: @pending, position: @position,
                      on_duty: Time.zone.local(YEAR, 8, 29, 10, 0, 0),
                      additional_notes: "still on duty")

    # An auditor is not in an active status, so hours alone must not list them.
    ranger_hours(person(:auditor_ranger), 25)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "admin and quartermaster may view the report" do
    [@admin, @quartermaster].each do |viewer|
      sign_in_as(viewer)
      get quartermaster_potential_shirts_path(year: YEAR)
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "denies access without the admin or quartermaster role" do
    sign_in_as(@outsider)
    get quartermaster_potential_shirts_path(year: YEAR)
    assert_response :redirect
  end

  test "lists people with hours, excluding Alpha shifters and non-active statuses" do
    get quartermaster_potential_shirts_path(year: YEAR)
    assert_response :success

    listed = listed_callsigns
    assert_includes listed, @earner.callsign
    assert_includes listed, @partial.callsign
    assert_includes listed, @pending.callsign, "a sign-up alone makes a candidate"
    assert_not_includes listed, @alpha_shifter.callsign, "Alpha shifters belong to the Alpha Shirts page"
    assert_not_includes listed, person(:auditor_ranger).callsign, "not an active status"
  end

  test "order lines count by full title and split earned from pending" do
    get quartermaster_potential_shirts_path(year: YEAR)
    assert_response :success

    tshirts = report_kind("T-Shirts")
    large = tshirts.lines.find { |line| line.title == @large.title }
    unknown = tshirts.lines.find { |line| line.title == ShirtTotals::UNKNOWN }

    assert_equal 2, large.earned, "earner and partial are both past #{SS_HOURS} hours"
    assert_equal 0, large.pending
    assert_equal 0, unknown.earned
    assert_equal 1, unknown.pending, "the sign-up-only person has no rangered hours and no size"

    long_sleeves = report_kind("Long Sleeves")
    medium = long_sleeves.lines.find { |line| line.title == @long_sleeve.title }
    assert_equal 1, medium.earned, "only the 45-hour earner is past #{LS_HOURS}"
    ls_unknown = long_sleeves.lines.find { |line| line.title == ShirtTotals::UNKNOWN }
    assert_equal 2, ls_unknown.pending, "partial and pending both lack a long sleeve size"
  end

  test "another year reports its own hours, not the selected fixtures" do
    get quartermaster_potential_shirts_path(year: 2018)
    assert_response :success
    assert_match "No one has hours toward a shirt in 2018", response.body
  end

  test "each filter narrows the roster" do
    [[{ earned: "t-shirt" }, [@earner, @partial]],
     [{ earned: "long-sleeve" }, [@earner]],
     [{ earned: "none" }, [@pending]],
     [{ tshirt: @large.title }, [@earner, @partial]],
     [{ long_sleeve: ShirtTotals::UNKNOWN }, [@partial, @pending]],
     [{ missing: "1" }, [@partial, @pending]],
     [{ earned: "long-sleeve", missing: "1" }, []]].each do |filters, expected|
      get quartermaster_potential_shirts_path(year: YEAR, **filters)

      assert_response :success
      assert_equal expected.map(&:callsign).sort, listed_callsigns.sort, filters.inspect
    end
  end

  # The first year-scoped quartermaster page: the filter form must carry the
  # year, or applying a filter snaps the report back to the current year.
  test "the filter form and chip URLs carry the year" do
    get quartermaster_potential_shirts_path(year: YEAR, earned: "t-shirt")
    assert_response :success

    assert_select "#potential-shirts-filters input[name=year][value=?]", YEAR.to_s
    assert_select "a[aria-label^=?][href*=?]", "Remove filter", "year=#{YEAR}"
  end

  test "roster CSV carries the filters, the year, and not-earned markers" do
    get quartermaster_potential_shirts_path(year: YEAR, format: :csv)
    assert_response :success
    assert_match "#{YEAR}-potential-shirts.csv", response.headers["Content-Disposition"]

    rows = response.body.split("\n")
    # Literal on purpose: an expectation built from the controller's own
    # roster_header moves together with the code under test.
    assert_equal "Callsign,First Name,Last Name,Estimated Hours in 2019,Hours in 2019," \
                 "T-Shirt (18 hrs),T-Shirt Backup,Long Sleeve (40 hrs)",
                 rows.first
    assert_equal 4, rows.size, "header plus the three candidates"

    partial_row = rows.find { |row| row.start_with?(@partial.callsign) }
    assert_match "not earned", partial_row, "the unearned long sleeve prints as not earned"

    get quartermaster_potential_shirts_path(year: YEAR, earned: "long-sleeve", format: :csv)
    assert_equal 2, response.body.split("\n").size, "the roster export follows the filters"
  end

  test "counts CSV is the whole report with kind, earned, and pending per row" do
    get quartermaster_potential_shirts_counts_path(year: YEAR)
    assert_response :success
    assert_match "#{YEAR}-potential-shirt-counts.csv", response.headers["Content-Disposition"]

    rows = response.body.split("\n")
    assert_equal "Shirt Kind,Shirt,Earned,Pending", rows.first
    assert rows.size > 1, "the counts export must carry the order lines"
    assert rows.drop(1).all? { |row| ShirtTotals::KINDS.any? { |kind| row.start_with?(kind[:name]) } }
    # Column order pinned: earner and partial both earned the large t-shirt;
    # only the 45-hour earner is past the long-sleeve line.
    assert_includes rows, "T-Shirts,#{@large.title},2,0"
    assert_includes rows, "Long Sleeves,#{@long_sleeve.title},1,0"
  end

  # Scoped to the sidebar element: the page's own export links also contain
  # the path, so an unscoped match cannot fail when the menu entry is gone.
  test "a quartermaster sees Potential Shirts in the sidebar but not Swag" do
    sign_in_as(@quartermaster)
    get quartermaster_potential_shirts_path(year: YEAR)

    assert_select "#sidebar-drawer-content a[href=?]",
                  quartermaster_potential_shirts_path(year: YEAR)
    assert_select "#sidebar-drawer-content a[href=?]", quartermaster_swag_path, count: 0
  end

  # The invariants the report documents, at their boundaries: hours at
  # exactly the threshold earn, uncounted positions and open entries add
  # nothing, and the sign-up-only person's rangered hours stay zero.
  test "threshold boundaries, uncounted positions, and open entries" do
    boundary = person(:plate_collision_ranger)
    uncounted = Position.create!(title: "Uncounted Position", count_hours: false)

    Timesheet.create!(person: boundary, position: @position,
                      on_duty: Time.zone.local(YEAR, 8, 26, 0, 0, 0),
                      off_duty: Time.zone.local(YEAR, 8, 26, 0, 0, 0) + SS_HOURS.hours,
                      additional_notes: "exactly the t-shirt threshold")
    Timesheet.create!(person: boundary, position: uncounted,
                      on_duty: Time.zone.local(YEAR, 8, 27, 0, 0, 0),
                      off_duty: Time.zone.local(YEAR, 8, 27, 12, 0, 0),
                      additional_notes: "not a counted position")

    row = report_rows.find { |candidate| candidate.person.id == boundary.id }

    assert_not_nil row
    assert_equal 18.0, row.actual_hours, "only the counted, closed entry may count"
    assert row.earned_ss, "hours at exactly the threshold earn the shirt"
    assert_not row.earned_ls

    pending = report_rows.find { |candidate| candidate.person.id == @pending.id }
    assert_equal 0.0, pending.actual_hours, "an open entry is not rangered hours"
  end

  private

  def ranger_hours(person, hours)
    Timesheet.create!(person:, position: @position,
                      on_duty: Time.zone.local(YEAR, 8, 26, 0, 0, 0),
                      off_duty: Time.zone.local(YEAR, 8, 26, 0, 0, 0) + hours.hours,
                      additional_notes: "test shift")
  end

  # The roster's first column. Order-line tables put their shirt title there
  # too, so the callsigns are whatever is left once titles are dropped.
  def listed_callsigns
    titles = report_rows.flat_map { |row|
      ShirtTotals::KINDS.map { |kind| ShirtTotals.title_for(row.person, kind[:reader]) }
    } | [ShirtTotals::UNKNOWN]

    css_select("th[scope=row]").map { |cell| cell.text.strip } - titles
  end

  def report_rows
    PotentialShirtsReport.execute(YEAR, threshold_ss: SS_HOURS, threshold_ls: LS_HOURS)
  end

  def report_kind(name)
    PotentialShirtsReport.order_lines(report_rows).find { |kind| kind.name == name }
  end
end
