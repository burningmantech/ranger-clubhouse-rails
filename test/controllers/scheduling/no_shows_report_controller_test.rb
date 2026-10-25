# frozen_string_literal: true

require "test_helper"

class Scheduling::NoShowsReportControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include EscapedMarkupTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2031

  setup do
    Rails.cache.clear
    Current.reset

    @now = Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    travel_to @now

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_SLOTS, "Edit Slots")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")

    @admin = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)

    @ood = positions(:ood_position)
    @mentor = positions(:mentor_lead)

    sign_in_as(@admin)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  # Timesheet#associate_slot links a new sign-on to a matching slot by itself,
  # so the linkage is set afterwards to exactly what the test asked for.
  def create_timesheet(person, position, on_duty:, off_duty: nil, slot: nil)
    timesheet = Timesheet.create!(person:, position:, on_duty:, off_duty:,
                                  additional_notes: "test shift")
    timesheet.update_columns(slot_id: slot&.id)
    timesheet
  end

  # @admin signs up for an OOD shift and is on duty for Mentor Lead instead.
  def build_shift
    @slot = create_slot(@ood, begins: @now - 6.hours, ends: @now + 6.hours)
    PersonSlot.create!(person: @admin, slot: @slot)
    create_timesheet(@admin, @mentor, on_duty: @slot.begins + 1.hour,
                                      off_duty: @slot.begins + 3.hours)
  end

  def position_path(year: YEAR, **options)
    scheduling_no_shows_report_position_path(@ood.id, year:, **options)
  end

  # --- Authorization ------------------------------------------------------

  # Upstream TimesheetPolicy: before admits Admin and Timesheet Management,
  # noShowsReport() admits Event Management.
  test "admin, timesheet management, and event management may all view the report" do
    timesheet_manager = person(:auditor_ranger)
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)

    [@admin, @event_manager, timesheet_manager].each do |viewer|
      sign_in_as(viewer)
      get scheduling_no_shows_report_path(year: YEAR)
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  # The flake report next door admits Edit Slots. This one hangs off the
  # timesheet policy, which never has.
  test "edit slots does not reach this report" do
    grant_role(@outsider, Role::EDIT_SLOTS)
    sign_in_as(@outsider)

    get scheduling_no_shows_report_path(year: YEAR)
    assert_redirected_to me_root_path
  end

  test "someone without the role is turned away from both pages" do
    sign_in_as(@outsider)

    get scheduling_no_shows_report_path(year: YEAR)
    assert_redirected_to me_root_path

    get position_path
    assert_redirected_to me_root_path
  end

  # The two reports point at each other, but their role sets only overlap.
  # Timesheet Management reads this page and not the flake report, so an
  # unguarded cross-link hands that reader a link that bounces to /me.
  test "the flake report cross-link is shown only to readers who may open it" do
    get scheduling_no_shows_report_path(year: YEAR)
    assert_select "a[href=?]", scheduling_flake_report_path(year: YEAR)

    timesheet_manager = person(:auditor_ranger)
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)
    sign_in_as(timesheet_manager)

    get scheduling_no_shows_report_path(year: YEAR)
    assert_response :success
    assert_select "a[href=?]", scheduling_flake_report_path(year: YEAR), count: 0
  end

  # --- Positions index ----------------------------------------------------

  test "the index lists each position with its shift and no show counts" do
    build_shift

    get scheduling_no_shows_report_path(year: YEAR)

    assert_response :success
    assert_select "a[href=?]", position_path, text: /#{Regexp.escape(@ood.title)}/
    assert_select "span.badge", text: /1 no show/
    assert_select "*", text: /1 no show on 1 shift/
  end

  test "a position everyone showed up for carries no badge at all" do
    slot = create_slot(@ood, begins: @now - 6.hours, ends: @now + 6.hours)
    PersonSlot.create!(person: @admin, slot:)
    create_timesheet(@admin, @ood, on_duty: slot.begins, off_duty: slot.ends)

    get scheduling_no_shows_report_path(year: YEAR)

    assert_response :success
    assert_select "a[href=?]", position_path
    assert_select "span.badge", count: 0
  end

  test "the index says so when the year has no shifts" do
    get scheduling_no_shows_report_path(year: YEAR)

    assert_response :success
    assert_select "*", text: /No #{YEAR} shifts have started yet/
  end

  # A shift that has not begun is not a shift anyone failed to show for.
  test "shifts that have not started yet are left out" do
    future = create_slot(@ood, begins: @now + 2.hours, ends: @now + 8.hours)
    PersonSlot.create!(person: @admin, slot: future)

    get scheduling_no_shows_report_path(year: YEAR)

    assert_response :success
    assert_select "*", text: /No #{YEAR} shifts have started yet/
  end

  test "drill-down links carry the requested year, not the current one" do
    past = create_slot(@ood, begins: Time.zone.local(YEAR - 1, 8, 26, 6, 0, 0),
                             ends: Time.zone.local(YEAR - 1, 8, 26, 18, 0, 0))
    PersonSlot.create!(person: @admin, slot: past)

    get scheduling_no_shows_report_path(year: YEAR - 1)

    assert_response :success
    assert_select "a[href=?]", position_path(year: YEAR - 1)
    assert_select "a[href=?]", position_path(year: YEAR), count: 0
  end

  # --- Position drill-down ------------------------------------------------

  test "the drill-down names the people who did not turn up" do
    build_shift

    get position_path

    assert_response :success
    assert_select "td", text: /#{Regexp.escape(@admin.callsign)}/
    assert_select "*", text: /1 of 1 sign-up/
    # datetime_format hands back a <span>; interpolating it rather than joining
    # it prints the markup on the page.
    assert_no_escaped_markup
  end

  # The attendance rule: a timesheet in the shift's own position that overlaps
  # it answers the sign-up, whether or not it was ever linked to the shift.
  test "a sign-up on duty for this position is not reported" do
    slot = create_slot(@ood, begins: @now - 6.hours, ends: @now + 6.hours)
    PersonSlot.create!(person: @admin, slot:)
    create_timesheet(@admin, @ood, on_duty: slot.begins, off_duty: slot.ends)

    get position_path

    assert_response :success
    assert_select "*", text: /No #{YEAR} shift of this position had a no show/
  end

  # Upstream's five OR'd branches had no case for an open timesheet, so the
  # person still out on the playa was reported as having missed the shift.
  test "an open timesheet started inside the shift answers the sign-up" do
    slot = create_slot(@ood, begins: @now - 6.hours, ends: @now + 6.hours)
    PersonSlot.create!(person: @admin, slot:)
    create_timesheet(@admin, @ood, on_duty: slot.begins + 1.hour, off_duty: nil)

    get position_path

    assert_response :success
    assert_select "*", text: /No #{YEAR} shift of this position had a no show/
  end

  # The whole difference from the flake report: that one excuses a sign-up
  # whose timesheet names the shift. This report asks only whether the hours
  # overlapped, so a linked timesheet that never touched the shift is still a
  # miss.
  test "a timesheet linked to the shift but outside its hours is still a no show" do
    slot = create_slot(@ood, begins: @now - 6.hours, ends: @now - 2.hours)
    PersonSlot.create!(person: @admin, slot:)
    create_timesheet(@admin, @ood, on_duty: slot.ends + 1.hour,
                                   off_duty: slot.ends + 2.hours, slot:)

    get position_path

    assert_response :success
    assert_select "td", text: /#{Regexp.escape(@admin.callsign)}/
  end

  # A timesheet signing off at the instant the shift begins is the standard
  # handover, not coverage.
  test "a timesheet that ends as the shift starts does not answer the sign-up" do
    slot = create_slot(@ood, begins: @now - 6.hours, ends: @now)
    PersonSlot.create!(person: @admin, slot:)
    create_timesheet(@admin, @ood, on_duty: slot.begins - 4.hours, off_duty: slot.begins)

    get position_path

    assert_response :success
    assert_select "td", text: /#{Regexp.escape(@admin.callsign)}/
  end

  test "the drill-down says so when the position has no started shifts" do
    get position_path

    assert_response :success
    assert_select "*", text: /No #{YEAR} shifts of this position have started yet/
  end

  test "an unknown position bounces back to the index" do
    get scheduling_no_shows_report_position_path(0, year: YEAR)

    assert_redirected_to scheduling_no_shows_report_path(year: YEAR)
  end

  # --- Export -------------------------------------------------------------

  test "the export carries one row per person per shift" do
    build_shift

    get position_path(format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.body, "Position,Shift Start,Shift,Callsign"
    assert_includes response.body, @admin.callsign
    assert_includes response.body, @ood.title
  end
end
