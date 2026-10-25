# frozen_string_literal: true

require "test_helper"

class Timesheets::TimesheetSlotRepairControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include BulkSelectTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  # A year the timesheet fixtures leave alone -- they carry 2023, 2024, and
  # 2025 entries, which would ride along in every count.
  YEAR = 2021

  setup do
    Rails.cache.clear
    Current.reset

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")

    @admin = person(:active_ranger)
    @timesheet_manager = person(:auditor_ranger)
    @event_manager = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@timesheet_manager, Role::TIMESHEET_MANAGEMENT)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)

    @position = positions(:ood_position)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def august(day, hour = 12, minute = 0)
    Time.zone.local(YEAR, 8, day, hour, minute, 0)
  end

  def shift(begins, description: "Test Shift")
    Slot.create!(position: @position, begins:, ends: begins + 6.hours,
                 description:, max: 10, active: true)
  end

  # An entry needing repair: it lines up with the shift but points at nothing.
  def unlinked_entry(on_duty: august(20, 17, 45), who: @admin)
    Timesheet.create!(person: who, position: @position, on_duty:,
                      off_duty: on_duty + 4.hours, additional_notes: "test entry")
            .tap { _1.update_column(:slot_id, nil) }
  end

  # --- the gate ----------------------------------------------------------

  test "an admin may read the page" do
    get timesheets_timesheet_slot_repair_path(year: YEAR)
    assert_response :success
  end

  test "timesheet management may read the page" do
    sign_in_as(@timesheet_manager)
    get timesheets_timesheet_slot_repair_path(year: YEAR)
    assert_response :success
  end

  # Upstream's Ember route asked for Tech Ninja while its policy refused
  # everyone but Admin and Timesheet Management. The API wins.
  test "tech ninja alone may not read the page" do
    grant_role(@outsider, Role::TECH_NINJA)
    sign_in_as(@outsider)
    get timesheets_timesheet_slot_repair_path(year: YEAR)
    assert_redirected_to me_root_path
  end

  test "event management may not read the page" do
    sign_in_as(@event_manager)
    get timesheets_timesheet_slot_repair_path(year: YEAR)
    assert_redirected_to me_root_path
  end

  test "a person with no role may not read the page" do
    sign_in_as(@outsider)
    get timesheets_timesheet_slot_repair_path(year: YEAR)
    assert_redirected_to me_root_path
  end

  test "the same gate covers the repair itself" do
    shift(august(20, 18))
    row = unlinked_entry
    sign_in_as(@event_manager)

    post timesheets_apply_timesheet_slot_repair_path(year: YEAR),
         params: { timesheet_ids: [row.id] }

    assert_redirected_to me_root_path
    assert_nil row.reload.slot_id
  end

  # --- the preview -------------------------------------------------------

  test "a clean year says so and offers no form" do
    shift(august(20, 18))
    Timesheet.create!(person: @admin, position: @position, on_duty: august(20, 17, 45),
                      off_duty: august(20, 21), additional_notes: "test entry")

    get timesheets_timesheet_slot_repair_path(year: YEAR)

    assert_response :success
    assert_match "nothing to repair", response.body
    assert_select "form[action=?]",
                  timesheets_apply_timesheet_slot_repair_path(year: YEAR), false
  end

  # A year with no entries has not been checked clean -- there was nothing to
  # check. The two empty states must not say the same thing.
  test "a year with no entries says there was nothing to check" do
    get timesheets_timesheet_slot_repair_path(year: YEAR)

    assert_response :success
    assert_match "no #{YEAR} timesheet entries to check", response.body
    assert_no_match(/nothing to repair/, response.body)
  end

  # A bare string reaches the app's confirm hook with no element to mount, and
  # degrades to the native browser dialog instead of the shared modal.
  test "the apply button confirms through the shared modal" do
    shift(august(20, 18))
    unlinked_entry

    get timesheets_timesheet_slot_repair_path(year: YEAR)

    assert_response :success
    assert_select "button[data-turbo-confirm*=?]", "turbo-confirm-button"
  end

  test "reading the page changes nothing" do
    shift(august(20, 18))
    row = unlinked_entry

    assert_no_difference ["TimesheetLog.count", "ActionLog.count"] do
      get timesheets_timesheet_slot_repair_path(year: YEAR)
    end

    assert_response :success
    assert_nil row.reload.slot_id
  end

  test "a proposed change is listed with a checkbox and both ends of the change" do
    shift(august(20, 18), description: "Swing Shift")
    row = unlinked_entry

    get timesheets_timesheet_slot_repair_path(year: YEAR)

    assert_response :success
    assert_select "input[name=?][value=?]", "timesheet_ids[]", row.id.to_s
    assert_match "Swing Shift", response.body
    assert_match "Entries with no shift", response.body
  end

  test "the year selector floor matches upstream" do
    get timesheets_timesheet_slot_repair_path(year: YEAR)

    assert_response :success
    assert_select "option[value=?]", "2010"
    assert_select "option[value=?]", "2009", false
  end

  # The hero panel builds its list without the chosen year, so any year the URL
  # can reach has to be in the list on its own -- including the two the event
  # did not happen in.
  test "every year the page accepts can be shown as chosen" do
    (2010..Current.year).each do |year|
      get timesheets_timesheet_slot_repair_path(year:)

      assert_response :success
      assert_select "h1", text: /\A#{year} /
      assert_select "option[value=?][selected]", year.to_s
    end
  end

  # Dropping a link loses the only record of which shift the entry belonged to,
  # so those rows are never carried along by "select all".
  test "a removal starts unticked and is passed over by select all" do
    stale = shift(august(17, 18))
    row = unlinked_entry
    row.update_column(:slot_id, stale.id)

    get timesheets_timesheet_slot_repair_path(year: YEAR)

    assert_response :success
    assert_select "input[name=?][value=?]", "timesheet_ids[]", row.id.to_s do |inputs|
      assert_nil inputs.first["checked"]
      assert_equal "true", inputs.first["data-skip-select-all"]
    end
  end

  test "an addition starts ticked" do
    shift(august(20, 18))
    row = unlinked_entry

    get timesheets_timesheet_slot_repair_path(year: YEAR)

    assert_select "input[name=?][value=?]", "timesheet_ids[]", row.id.to_s do |inputs|
      assert_equal "checked", inputs.first["checked"]
    end
    assert_bulk_select_count_matches_ticked
  end

  # --- applying ----------------------------------------------------------

  test "applying relinks the selected entry and reports it" do
    match = shift(august(20, 18), description: "Swing Shift")
    row = unlinked_entry

    post timesheets_apply_timesheet_slot_repair_path(year: YEAR),
         params: { timesheet_ids: [row.id] }

    assert_response :unprocessable_entity
    assert_equal match.id, row.reload.slot_id
    assert_match "1 Entry Relinked", response.body
    assert_select "[data-controller=scroll-to-top]"
  end

  test "an unselected entry is left alone" do
    shift(august(20, 18))
    selected = unlinked_entry
    untouched = unlinked_entry(on_duty: august(20, 17, 50), who: @timesheet_manager)

    post timesheets_apply_timesheet_slot_repair_path(year: YEAR),
         params: { timesheet_ids: [selected.id] }

    assert_response :unprocessable_entity
    assert_not_nil selected.reload.slot_id
    assert_nil untouched.reload.slot_id
  end

  test "submitting nothing says so rather than repairing everything" do
    shift(august(20, 18))
    row = unlinked_entry

    post timesheets_apply_timesheet_slot_repair_path(year: YEAR)

    assert_response :unprocessable_entity
    assert_match "Nothing Was Selected", response.body
    assert_nil row.reload.slot_id
  end

  test "an entry that no longer needs repairing is reported as left alone" do
    match = shift(august(20, 18))
    row = unlinked_entry
    row.update_column(:slot_id, match.id)

    post timesheets_apply_timesheet_slot_repair_path(year: YEAR),
         params: { timesheet_ids: [row.id] }

    assert_response :unprocessable_entity
    assert_match "no longer needs repairing", response.body
  end

  test "an entry id from another year is not repaired" do
    shift(august(20, 18))
    row = unlinked_entry

    post timesheets_apply_timesheet_slot_repair_path(year: YEAR + 1),
         params: { timesheet_ids: [row.id] }

    assert_response :unprocessable_entity
    assert_nil row.reload.slot_id
  end
end
