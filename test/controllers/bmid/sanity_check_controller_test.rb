# frozen_string_literal: true

require "test_helper"

# BMID > Sanity Check: who may look, and how the merged findings table, the
# check filter, and the box-office note render.
#
# The report logic itself is covered by BmidSanityCheckReportTest; these tests
# seed one flagged person (or one flagged by two checks) and read the page.
class Bmid::SanityCheckControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers
  include TicketingTestHelper
  include ReportCardTestHelper # card_answer / assert_no_card_question

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 4, 8, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @badger = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_BMIDS, "Edit BMIDs")
    grant_role(@admin, Role::ADMIN)
    grant_role(@badger, Role::EDIT_BMIDS)

    AccessDocument.delete_all
    PersonSlot.delete_all
    Slot.delete_all
    Setting.where(name: Setting::TAS_BOX_OFFICE_OPEN_DATE).delete_all
    Setting.create!(name: Setting::TAS_BOX_OFFICE_OPEN_DATE, value: "#{YEAR}-08-26 12:00:00")

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- who may look ---------------------------------------------------------

  test "the report renders for an admin" do
    flag_ranger(@admin)

    get bmid_sanity_check_path

    assert_response :success
    assert_match @admin.callsign, response.body
    assert_match "Showing 1 of 1 finding", response.body
    assert_match "No usable SAP or Staff Credential.", response.body
    # Below lg each finding folds into a labelled card: as a table, an email
    # address that cannot break pushed a phone's page sideways.
    assert_select "#findings-section div.table-container.w-fit > table.responsive-table"
    assert_select "#findings-section td[data-label=Check]", text: /No SAP/
  end

  test "the report renders with only the edit BMIDs role" do
    sign_in_as(@badger)
    flag_ranger(@badger)

    get bmid_sanity_check_path

    assert_response :success
    assert_match @badger.callsign, response.body
  end

  # Whatever year a link carries, the page checks the current one and says so.
  test "a link carrying a past year still checks the current year" do
    flag_ranger(@admin)

    get bmid_sanity_check_path(year: YEAR - 1)

    assert_response :success
    assert_select "h1", text: /#{YEAR} BMID Sanity Check/
    assert_select "#year-selector", count: 0
    assert_match "only available for the current year's badges", response.body
    assert_match "Showing 1 of 1 finding", response.body
  end

  test "the report is refused without the admin or edit BMIDs role" do
    sign_in_as(@outsider)

    get bmid_sanity_check_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit BMIDs role required to manage BMIDs.", flash[:error]
  end

  # --- the merged table and its filter --------------------------------------

  test "a person flagged by two checks appears once per finding" do
    flag_ranger_twice(@admin)

    get bmid_sanity_check_path

    assert_select "#findings-section tbody tr", 2
  end

  test "the check filter narrows the table and unknown values are ignored" do
    flag_ranger_twice(@admin)

    get bmid_sanity_check_path(check: "spt_before_box_office")
    assert_match "Showing 1 of 2 findings", response.body
    assert_select "#findings-section tbody tr", 1

    get bmid_sanity_check_path(check: "bogus")
    assert_match "Showing 2 of 2 findings", response.body

    # A clean check names itself rather than showing an empty table.
    get bmid_sanity_check_path(check: "shifts_no_wap")
    assert_match "No findings for", response.body
    assert_match "Pre-event shifts with no SAP", response.body
  end

  # A tile's link name replaces its text for a screen reader, so it carries
  # the tile's count as well as the check it narrows to.
  test "each tile's link names its check and its count" do
    flag_ranger_twice(@admin)

    get bmid_sanity_check_path

    assert_select "a[aria-label=?]", "Show only Shifts before SAP access date, 1 finding"
    assert_select "a[aria-label=?]", "Show only Pre-event shifts with no SAP, 0 findings"
  end

  test "a clean year says so" do
    get bmid_sanity_check_path

    assert_response :success
    assert_match "No findings for #{YEAR}", response.body
  end

  # The report owns the check list; the helper decorates it. A key added to
  # one without the other means a missing tile or a KeyError mid-render, so
  # the sync is pinned here.
  test "every report check has tile and filter metadata" do
    assert_equal BmidSanityCheckReport::CHECK_KEYS, Bmid::SanityCheckHelper::CHECK_META.keys
  end

  # --- the box-office note --------------------------------------------------

  test "a blank box office setting is called out instead of crashing the page" do
    Setting.where(name: Setting::TAS_BOX_OFFICE_OPEN_DATE).delete_all

    get bmid_sanity_check_path

    assert_response :success
    assert_match "TAS_BoxOfficeOpenDate", response.body
  end

  # The definition names the date it measures against, so it is in the card
  # only while that date is set. With the date gone the warning speaks instead.
  test "the card defines SPT early access only while the box office date is set" do
    question = "What is #{Bmid::SanityCheckHelper::CHECK_META[:spt_before_box_office][:short_label]}?"

    get bmid_sanity_check_path

    assert_match(/before the box office opens on/, card_answer(question))

    Setting.where(name: Setting::TAS_BOX_OFFICE_OPEN_DATE).delete_all
    get bmid_sanity_check_path

    assert_match "TAS_BoxOfficeOpenDate", response.body
    assert_no_card_question question
  end

  private

  # An early shift and no access document: one no-SAP finding (check 3).
  def flag_ranger(holder)
    sign_up(holder, slot_for(999, begins: Time.zone.local(YEAR, 8, 20, 12, 0, 0)))
  end

  # The same shift plus a dated SAP after it (check 1) that also opens before
  # the box office alongside a live SPT (check 4): two findings, one person.
  def flag_ranger_twice(holder)
    flag_ranger(holder)
    document(holder, status: AccessDocument::CLAIMED,
                     access_date: Time.zone.local(YEAR, 8, 23, 12, 0, 0))
    document(holder, type: AccessDocument::SPT, status: AccessDocument::CLAIMED)
  end
end
