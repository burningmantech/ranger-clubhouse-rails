# frozen_string_literal: true

require "test_helper"

# Payroll Missing ID: who holds a paid sign-up in the year with no Paycom
# Employee ID to be paid against, and who is set to the "0" that clears them to
# take it unpaid.
class ShiftOperations::PayrollMissingIdControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper   # create_slot
  include PersonTestFactory        # create_person

  # At or above the page's 2023 floor and never in the future: setup_year swaps
  # either for the current year.
  YEAR = 2025

  MISSING = "payroll-missing-id-missing"
  UNPAID = "payroll-missing-id-unpaid"

  setup do
    Rails.cache.clear
    Current.reset

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::PAYROLL, "Payroll")

    @admin = person(:active_ranger)
    @clerk = person(:echelon_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@clerk, Role::PAYROLL)

    @paid = Position.create!(title: "Payroll Dirt", active: true, paycode: "DIRT")

    sign_in_as(@clerk)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def august(day, hour = 10, year: YEAR)
    Time.zone.local(year, 8, day, hour, 0, 0)
  end

  # A sign-up: a fresh slot on the position, and the person on it.
  def sign_up(person, position: @paid, begins: august(28))
    PersonSlot.create!(person:, slot: create_slot(position, begins:))
  end

  def callsigns_in(section)
    css_select("##{section} th[scope=row]").map { |cell| cell.text.squish }
  end

  def report_path(**) = shift_operations_payroll_missing_id_path(year: YEAR, **)

  # --- Access -------------------------------------------------------------

  test "payroll and admin may open the page" do
    [@clerk, @admin].each do |reader|
      sign_in_as(reader)
      get report_path
      assert_response :success, "#{reader.callsign} should be let in"
    end
  end

  test "timesheet management is turned away" do
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")
    manager = person(:inactive_ranger)
    grant_role(manager, Role::TIMESHEET_MANAGEMENT)
    sign_in_as(manager)

    get report_path

    assert_redirected_to me_root_path
    assert_equal "Payroll role required to view people missing a Paycom Employee ID.", flash[:error]
  end

  # --- Who is listed ------------------------------------------------------

  test "no id and a blank id are both missing, in callsign order" do
    blank = create_person("Blanket")
    # update_column, not update!: Person's setter would save the "" as nil, and a
    # row written around it must still be found.
    blank.update_column(:employee_id, "")
    none = create_person("Anteater")
    settled = create_person("Settled")
    settled.update!(employee_id: "E-1001")
    [blank, none, settled].each { |person| sign_up(person) }

    get report_path

    assert_equal %w[Anteater Blanket], callsigns_in(MISSING)
    # Both halves are drawn once anyone is listed, and the empty one says so.
    assert_select "##{UNPAID}", text: /Set to 0.*No one signed up for a paid shift in #{YEAR} is set to 0\./m
    # The export's own href, so the empty-year test's count: 0 cannot pass by
    # looking for a link spelled differently.
    assert_select "a[href=?]", report_path(format: :csv)
  end

  # The database decides which ids are the 0, not Ruby: its collation matches a
  # trailing space and a no-break space alike, and whatever it matched as the 0
  # has to land in this half rather than under "No ID on File".
  test "a 0 is listed in its own section, not with the missing" do
    zeroed = create_person("Zeroed")
    zeroed.update!(employee_id: "0")
    spaced = create_person("Spaced")
    spaced.update_column(:employee_id, "0 ")
    unbroken = create_person("Nbsp")
    unbroken.update_column(:employee_id, "0 ")
    [zeroed, spaced, unbroken].each { |person| sign_up(person) }

    get report_path

    assert_equal %w[Nbsp Spaced Zeroed], callsigns_in(UNPAID)
    assert_select "##{MISSING}",
                  text: /No ID on File.*No one signed up for a paid shift in #{YEAR} is missing a Paycom Employee ID\./m
  end

  test "only paid positions in the chosen year count" do
    legacy = Position.create!(title: "Legacy Blank Paycode", active: true)
    # normalize_blank_attributes turns "" into nil on save, and production
    # still holds dozens of positions carrying the old "".
    legacy.update_column(:paycode, "")
    someone = create_person("Unpaidpos")
    sign_up(someone, position: positions(:ood_position))
    sign_up(someone, position: legacy)
    sign_up(someone, begins: august(28, year: YEAR - 1))

    get report_path

    assert_includes response.body, "No one is signed up for a paid shift in #{YEAR}."
    assert_select "##{MISSING}", count: 0
    assert_select "a[href=?]", report_path(format: :csv), count: 0
  end

  # Kept apart from the year with no paid sign-ups at all: there, "everyone has
  # an ID" would be true of nobody.
  test "a year where every paid sign-up has an id says so" do
    settled = create_person("Settled")
    settled.update!(employee_id: "E-1001")
    sign_up(settled)

    get report_path

    assert_includes response.body, "Everyone signed up for a paid shift in #{YEAR} has a Paycom Employee ID."
    assert_select "##{MISSING}", count: 0
  end

  test "one row per person, however many paid shifts" do
    tow = Position.create!(title: "Payroll Tow", active: true, paycode: "TOW")
    busy = create_person("Busybody")
    sign_up(busy, begins: august(29))
    sign_up(busy, position: tow, begins: august(27))
    sign_up(busy, begins: august(30))

    get report_path

    assert_equal %w[Busybody], callsigns_in(MISSING)
    assert_select "##{MISSING} td[data-label='Paid Shifts']", text: "3"
    # First-shift order: Tow opens the week, although Dirt comes first by title,
    # by position id, and by the order the sign-ups were made in.
    assert_select "##{MISSING} td[data-label='Paid Positions']",
                  text: "Payroll Tow (TOW), Payroll Dirt (DIRT)"
    assert_select "##{MISSING} td[data-label='First Paid Shift']", text: /Aug 27 @ 10:00/
  end

  test "the year selector picks the year" do
    earlier = create_person("Lastyear")
    sign_up(earlier, begins: august(28, year: YEAR - 1))

    get shift_operations_payroll_missing_id_path(year: YEAR - 1)

    assert_equal %w[Lastyear], callsigns_in(MISSING)
  end

  # Paycom Employee IDs were first recorded in 2023, so an earlier year would
  # list everyone signed up for a position paid today.
  test "no year before 2023 is offered or honoured" do
    get shift_operations_payroll_missing_id_path(year: 2022)

    assert_select "select option[value='2023']"
    assert_select "select option[value='2022']", count: 0
    assert_select "h1", text: /2022/, count: 0
  end

  # --- Links --------------------------------------------------------------

  test "an admin's callsign opens external ids, and payroll's is plain text" do
    target = create_person("Linkable")
    sign_up(target)

    sign_in_as(@admin)
    get report_path
    assert_select "##{MISSING} th[scope=row] a[href=?]", person_external_ids_path(target),
                  text: "Linkable"

    # Payroll cannot open person pages, so a link would only bounce them.
    sign_in_as(@clerk)
    get report_path
    assert_equal %w[Linkable], callsigns_in(MISSING)
    assert_select "##{MISSING} th[scope=row] a", count: 0
  end

  # External IDs admits Admin only, so a reader who may open person pages but
  # not that one gets the person page -- a link to External IDs would bounce.
  test "a payroll clerk who may open person pages gets the person page" do
    ensure_role(Role::MENTOR, "Mentor")
    grant_role(@clerk, Role::MENTOR)
    target = create_person("Linkable")
    sign_up(target)

    get report_path

    assert_select "##{MISSING} th[scope=row] a[href=?]", person_path(target), text: "Linkable"
  end

  # The link reads External IDs' own gate, not the person-page one, so opening
  # that page to Payroll would reach clerks who still may not open person pages.
  test "the external ids link follows that page's own gate" do
    gate = Person::ExternalIdsController.authorized_roles
    Person::ExternalIdsController.authorized_roles = [Role::ADMIN, Role::PAYROLL]
    target = create_person("Linkable")
    sign_up(target)

    get report_path

    assert_select "##{MISSING} th[scope=row] a[href=?]", person_external_ids_path(target)
  ensure
    Person::ExternalIdsController.authorized_roles = gate
  end

  # --- CSV ----------------------------------------------------------------

  test "the csv lists the missing, then the 0s" do
    # The 0 comes first by callsign and by first shift, so only the order of
    # the halves can put the missing person ahead of it.
    zeroed = create_person("Aardvark")
    zeroed.update!(employee_id: "0")
    none = create_person("Zorilla")
    sign_up(zeroed, begins: august(26, 9))
    sign_up(none)

    get report_path(format: :csv)

    assert_response :success
    assert_match "#{YEAR}-payroll-missing-id.csv", response.headers["Content-Disposition"]
    # Whole lines: the id column is what tells the two halves apart here, and
    # a prefix match would pass without it.
    assert_equal ["Callsign,First Name,Last Name,Status,Paycom Employee ID," \
                  "Paid Positions,Paid Shifts,First Paid Shift",
                  "Zorilla,Zorilla,Shifter,active,,Payroll Dirt (DIRT),1,#{YEAR}-08-28 10:00",
                  "Aardvark,Aardvark,Shifter,active,0,Payroll Dirt (DIRT),1,#{YEAR}-08-26 09:00"],
                 response.body.split("\n")
  end
end
