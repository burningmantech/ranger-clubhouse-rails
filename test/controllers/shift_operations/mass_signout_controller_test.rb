# frozen_string_literal: true

require "test_helper"

class ShiftOperations::MassSignoutControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include BulkSelectTestHelper
  include EscapedMarkupTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2031

  setup do
    Rails.cache.clear
    Current.reset

    @now = Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    travel_to @now

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")
    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")

    @admin = person(:active_ranger)
    @ranger = person(:echelon_ranger)
    @inactive = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)

    @ood = positions(:ood_position)
    @mentor = positions(:mentor_lead)

    sign_in_as(@admin)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  def create_timesheet(person, position, on_duty:, off_duty: nil)
    Timesheet.create!(person:, position:, on_duty:, off_duty:,
                      additional_notes: "test shift")
  end

  # ---------------------------------------------------------------- access

  test "admin may open the page" do
    get shift_operations_mass_signout_path

    assert_response :success
  end

  # Timesheet Management reads every other timesheet report, and Shift
  # Management is what TimesheetPolicy@signoff actually asks for -- both are
  # plausible-but-wrong gates for a page the upstream menu keeps Admin-only.
  test "timesheet management and shift management are both turned away" do
    [Role::TIMESHEET_MANAGEMENT, Role::SHIFT_MANAGEMENT].each do |role_id|
      grant_role(@ranger, role_id)
      sign_in_as(@ranger)

      get shift_operations_mass_signout_path
      assert_redirected_to me_root_path, "role #{role_id} should not reach mass signout"
    end
  end

  test "a non-admin cannot post a signout either" do
    entry = create_timesheet(@ranger, @ood, on_duty: @now - 2.hours)
    sign_in_as(@ranger)

    post shift_operations_mass_signout_path, params: { ids: [entry.id] }

    assert_redirected_to me_root_path
    assert_nil entry.reload.off_duty
  end

  # ------------------------------------------------------------------ index

  test "an empty board says so" do
    get shift_operations_mass_signout_path

    assert_response :success
    assert_select "*", text: /No one is on duty right now/
  end

  test "a current entry renders checked and selectable by select-all" do
    entry = create_timesheet(@ranger, @ood, on_duty: @now - 2.hours)

    get shift_operations_mass_signout_path

    assert_response :success
    # Scoped to the bulk_select wrapper: the attribute only protects the row if
    # the Stimulus controller is actually driving that checkbox.
    assert_select "[data-controller=checkbox-select-all] #mass-signout-check-#{entry.id}[checked]"
    assert_select "#mass-signout-check-#{entry.id}[data-skip-select-all]", count: 0
    assert_select "#mass-signout-check-#{entry.id}[aria-label=?]", "Select #{@ranger.callsign}"
    assert_select "a", text: @ranger.callsign
  end

  # Neither the confirm modal nor the disable-until-checked wiring shows up in
  # any other assertion, so dropping either would otherwise pass silently -- and
  # dropping the first means a whole-board signout fires with no confirmation.
  test "the submit button confirms and disables itself when nothing is checked" do
    create_timesheet(@ranger, @ood, on_duty: @now - 2.hours)

    get shift_operations_mass_signout_path

    assert_select "input[type=submit][data-checkbox-select-all-target=submit]"
    assert_select "input[type=submit][data-turbo-confirm*=?]", "Confirm Mass Sign-Out"
    assert_select "[data-controller=checkbox-select-all] [data-checkbox-select-all-target=toggle]"
  end

  # The whole point of the page: the entry OnDutyReport hides shows up here,
  # unchecked, and "select all" cannot arm it.
  #
  # A current entry rides along on purpose. With only the stale row on the board
  # stale_rows and rows are the same list, so swapping one for the other in the
  # callout -- telling admins not to sign out everybody -- would pass unnoticed.
  test "an entry from a past event renders unchecked, skipped, and called out" do
    stale = create_timesheet(@ranger, @ood, on_duty: @now - 3.years)
    current = create_timesheet(@admin, @mentor, on_duty: @now - 2.hours)

    get shift_operations_mass_signout_path

    assert_response :success
    assert_select "#mass-signout-check-#{stale.id}[checked]", count: 0
    assert_select "[data-controller=checkbox-select-all] " \
                  "#mass-signout-check-#{stale.id}[data-skip-select-all]"
    # The tint and the icon are not announced; the control's own name is.
    assert_select "#mass-signout-check-#{stale.id}" \
                  "[aria-label*='entry left open since a past event']"
    assert_select "#mass-signout-row-#{stale.id} i.fa-triangle-exclamation"
    # Its year is the tell, and datetime_format hides the year by default.
    assert_select "#mass-signout-row-#{stale.id}", text: /#{@now.year - 3}/
    # datetime_format hands back a <span> -- joined, never interpolated.
    assert_no_escaped_markup

    # The callout names the stale Ranger and no one else.
    assert_select ".box-accent" do |callout|
      assert_match(/Do Not Sign These Out/, callout.text)
      assert_match(/#{@ranger.callsign}/, callout.text)
      assert_no_match(/#{@admin.callsign}/, callout.text)
    end
    assert_select "#mass-signout-check-#{current.id}[checked]"
    assert_bulk_select_count_matches_ticked
    # Every row select-all can arm starts ticked, so the toggle arrives ticked
    # rather than being flipped by the controller on load.
    assert_select "[data-checkbox-select-all-target=toggle][checked]"
  end

  # One Ranger, two forgotten events: the callout names people, so it must not
  # print the same callsign twice.
  test "two stale entries for one Ranger are named once in the callout" do
    create_timesheet(@ranger, @ood, on_duty: @now - 3.years)
    create_timesheet(@ranger, @mentor, on_duty: @now - 4.years)

    get shift_operations_mass_signout_path

    assert_select ".box-accent" do |callout|
      assert_equal 1, callout.text.scan(/#{@ranger.callsign}/).size
      assert_match(/is still on duty from a past event/, callout.text)
    end
  end

  # "Out over a day" is a superset of "from a past event" -- a 2019 entry has
  # certainly been out over a day, and reading 0 beside 1 contradicts the label.
  test "the stat boxes count a stale entry as also being out over a day" do
    create_timesheet(@ranger, @ood, on_duty: @now - 3.years)
    create_timesheet(@admin, @mentor, on_duty: @now - 30.hours)
    create_timesheet(@inactive, @ood, on_duty: @now - 1.hour)

    get shift_operations_mass_signout_path

    report = @controller.view_assigns["report"]
    assert_equal 3, report.total
    assert_equal 2, report.long_count
    assert_equal 1, report.stale_count
  end

  # No FK on person_id in the Laravel-shared schema, so a non-optional
  # belongs_to still reads nil. callsign_link raises on that, and one orphaned
  # row must not take the whole board down.
  test "an entry whose Ranger is gone still renders" do
    orphan = create_timesheet(@ranger, @ood, on_duty: @now - 2.hours)
    orphan.update_column(:person_id, 0)

    get shift_operations_mass_signout_path

    assert_response :success
    assert_select "#mass-signout-row-#{orphan.id}", text: /Deleted #0/
  end

  test "an entry open longer than a day is flagged but stays pre-selected" do
    long = create_timesheet(@ranger, @ood, on_duty: @now - 30.hours)

    get shift_operations_mass_signout_path

    assert_response :success
    assert_select "#mass-signout-check-#{long.id}[checked]"
    assert_select "#mass-signout-check-#{long.id}[data-skip-select-all]", count: 0
    # Past a day the clock reading stops being readable, so it switches units.
    assert_select "#mass-signout-row-#{long.id}", text: /1 day 6 hours/
  end

  # -------------------------------------------------------------- signout

  test "posting ids signs every one of them off and logs it" do
    first = create_timesheet(@ranger, @ood, on_duty: @now - 2.hours)
    second = create_timesheet(@admin, @mentor, on_duty: @now - 1.hour)

    post shift_operations_mass_signout_path, params: { ids: [first.id, second.id] }

    assert_redirected_to shift_operations_mass_signout_path
    assert_equal @now, first.reload.off_duty
    assert_equal @now, second.reload.off_duty
    assert_equal 2, TimesheetLog.where(timesheet_id: [first.id, second.id],
                                       action: TimesheetLog::SIGNOFF).count
    assert_equal "2 Rangers signed out.", flash[:success]
  end

  test "an unselected entry is left alone" do
    selected = create_timesheet(@ranger, @ood, on_duty: @now - 2.hours)
    untouched = create_timesheet(@admin, @mentor, on_duty: @now - 2.hours)

    post shift_operations_mass_signout_path, params: { ids: [selected.id] }

    assert_equal @now, selected.reload.off_duty
    assert_nil untouched.reload.off_duty
  end

  # HQ closed it between the page rendering and the form arriving. The id is no
  # longer in on_duty_now, so it is never touched and the count says so.
  test "an entry someone else already closed is not re-stamped and is reported" do
    closed_at = @now - 30.minutes
    closed = create_timesheet(@ranger, @ood, on_duty: @now - 2.hours, off_duty: closed_at)
    open = create_timesheet(@admin, @mentor, on_duty: @now - 1.hour)

    post shift_operations_mass_signout_path, params: { ids: [closed.id, open.id] }

    assert_equal closed_at, closed.reload.off_duty
    assert_equal @now, open.reload.off_duty
    assert_equal "1 Ranger signed out. 1 entry was no longer open.", flash[:success]
  end

  # Green on "0 Rangers signed out" would tell an admin the board is clear when
  # nothing happened at all.
  test "a sweep that closes nothing warns instead of reporting success" do
    closed = create_timesheet(@ranger, @ood, on_duty: @now - 2.hours, off_duty: @now - 1.hour)

    post shift_operations_mass_signout_path, params: { ids: [closed.id, 987_654_321] }

    assert_nil flash[:success]
    assert_equal "0 Rangers signed out. 2 entries were no longer open.", flash[:warning]
  end

  test "posting nothing asks for a selection instead of sweeping the board" do
    entry = create_timesheet(@ranger, @ood, on_duty: @now - 2.hours)

    post shift_operations_mass_signout_path

    assert_redirected_to shift_operations_mass_signout_path
    assert_equal "Select at least one Ranger to sign out.", flash[:error]
    assert_nil entry.reload.off_duty
  end

  # ids[] is never permitted, so a hand-built request can hand us a hash or a
  # bare string. Neither may reach `where`.
  test "a malformed ids parameter is refused rather than raising" do
    create_timesheet(@ranger, @ood, on_duty: @now - 2.hours)

    post shift_operations_mass_signout_path, params: { ids: { evil: "1" } }

    assert_redirected_to shift_operations_mass_signout_path
    assert_equal "Select at least one Ranger to sign out.", flash[:error]
  end

  # to_i read "abc" as entry 0, reported as no longer open, and "#{id}x" as
  # that entry, which it signed out.
  test "ids that are not ids are neither signed out nor counted" do
    entry = create_timesheet(@ranger, @ood, on_duty: @now - 2.hours)
    other = create_timesheet(@admin, @mentor, on_duty: @now - 1.hour)

    post shift_operations_mass_signout_path, params: { ids: [entry.id, "abc", "#{other.id}x"] }

    assert_equal "1 Ranger signed out.", flash[:success]
    assert_nil other.reload.off_duty
  end

  test "an inactive Ranger comes back Active and the flash names them" do
    entry = create_timesheet(@inactive, @ood, on_duty: @now - 2.hours)

    post shift_operations_mass_signout_path, params: { ids: [entry.id] }

    assert_equal Person::ACTIVE, @inactive.reload.status
    assert_equal "1 Ranger signed out. #{@inactive.callsign} was converted back to Active.",
                 flash[:success]
  end

  test "a stale entry a human deliberately checked is still signed out" do
    stale = create_timesheet(@ranger, @ood, on_duty: @now - 3.years)

    post shift_operations_mass_signout_path, params: { ids: [stale.id] }

    assert_equal @now, stale.reload.off_duty
  end

  test "two conversions are named with plural agreement" do
    # update_columns, not update! -- a real status write drags position grants
    # in behind it, and this test only needs the flash wording.
    second = person(:retired_ranger)
    second.update_columns(status: Person::INACTIVE)
    first = create_timesheet(@inactive, @ood, on_duty: @now - 2.hours)
    other = create_timesheet(second, @mentor, on_duty: @now - 1.hour)

    post shift_operations_mass_signout_path, params: { ids: [first.id, other.id] }

    assert_match(/were converted back to Active/, flash[:success])
    assert_match(/#{@inactive.callsign}/, flash[:success])
    assert_match(/#{second.callsign}/, flash[:success])
  end

  # TimesheetLog belongs_to a required :person, so an orphaned entry cannot be
  # signed off at all -- the audit write raises. It used to render pre-checked
  # and armed by select-all, which took the whole sweep down mid-loop after the
  # earlier rows were already committed. Now it is not offered, and a submitted
  # id for one is skipped and reported rather than raising.
  test "an orphaned entry is skipped and reported, and the rest of the sweep lands" do
    first = create_timesheet(@ranger, @ood, on_duty: @now - 2.hours)
    orphan = create_timesheet(@admin, @ood, on_duty: @now - 2.hours)
    orphan.update_column(:person_id, 0)
    last = create_timesheet(@inactive, @mentor, on_duty: @now - 1.hour)

    post shift_operations_mass_signout_path,
         params: { ids: [first.id, orphan.id, last.id] }

    assert_redirected_to shift_operations_mass_signout_path
    assert_equal @now, first.reload.off_duty
    assert_equal @now, last.reload.off_duty
    assert_nil orphan.reload.off_duty
    assert_match(/1 entry could not be signed out/, flash[:success])
  end

  test "an orphaned entry is not offered for selection" do
    orphan = create_timesheet(@ranger, @ood, on_duty: @now - 2.hours)
    orphan.update_column(:person_id, 0)

    get shift_operations_mass_signout_path

    assert_select "#mass-signout-check-#{orphan.id}[checked]", count: 0
    assert_select "#mass-signout-check-#{orphan.id}[data-skip-select-all]"
    assert_select "#mass-signout-check-#{orphan.id}[aria-label*='record is gone']"
  end

  # Same wall, one line further into convert_inactive_to_active.
  test "sweeping an inactive Ranger whose position is gone does not crash" do
    entry = create_timesheet(@inactive, @ood, on_duty: @now - 2.hours)
    entry.update_column(:position_id, 0)

    post shift_operations_mass_signout_path, params: { ids: [entry.id] }

    assert_redirected_to shift_operations_mass_signout_path
    assert_equal @now, entry.reload.off_duty
    # No position means no conversion decision can be made, so none is made.
    assert_equal Person::INACTIVE, @inactive.reload.status
  end
end
