# frozen_string_literal: true

require "test_helper"

class Scheduling::FlakeReportControllerTest < ActionDispatch::IntegrationTest
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

  # @admin flakes on an OOD shift while on duty for Mentor Lead; @outsider
  # rangers the shift without signing up.
  def build_shift
    @slot = create_slot(@ood, begins: @now - 6.hours, ends: @now + 6.hours)
    PersonSlot.create!(person: @admin, slot: @slot)
    create_timesheet(@admin, @mentor, on_duty: @slot.begins + 1.hour,
                                      off_duty: @slot.begins + 3.hours)
    create_timesheet(@outsider, @ood, on_duty: @slot.begins, off_duty: @slot.ends, slot: @slot)
  end

  def position_path(year: YEAR)
    scheduling_flake_report_position_path(@ood.id, year:)
  end

  # Upstream SlotPolicy: before admits Admin and Edit Slots, report() admits
  # Event Management.
  test "admin, edit slots, and event management may all view the report" do
    slot_editor = @outsider
    grant_role(slot_editor, Role::EDIT_SLOTS)

    [@admin, @event_manager, slot_editor].each do |viewer|
      sign_in_as(viewer)
      get scheduling_flake_report_path(year: YEAR)
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "someone without the role is turned away from both pages" do
    sign_in_as(@outsider)

    get scheduling_flake_report_path(year: YEAR)
    assert_redirected_to me_root_path

    get position_path
    assert_redirected_to me_root_path
  end

  # --- Positions index ----------------------------------------------------

  test "the index lists each position with its shift, flake, and rogue counts" do
    build_shift

    get scheduling_flake_report_path(year: YEAR)

    assert_response :success
    assert_select "a[href=?]", position_path, text: /#{Regexp.escape(@ood.title)}/
    assert_select "span.badge", text: /1 flake/
    assert_select "span.badge", text: /1 rogue/
  end

  test "a position with no flakes and no rogues carries no badge at all" do
    slot = create_slot(@ood, begins: @now - 6.hours, ends: @now + 6.hours)
    PersonSlot.create!(person: @admin, slot:)
    create_timesheet(@admin, @ood, on_duty: slot.begins, off_duty: slot.ends, slot:)

    get scheduling_flake_report_path(year: YEAR)

    assert_response :success
    assert_select "a[href=?]", position_path
    assert_select "span.badge", count: 0
  end

  # A shift no one signed up for produces neither a flake nor a rogue, so
  # without its own count it read as a clean shift.
  test "shifts no one signed up for are counted, not called covered" do
    create_slot(@ood, begins: @now - 6.hours, ends: @now + 6.hours)

    get scheduling_flake_report_path(year: YEAR)

    assert_response :success
    assert_select "span.badge", text: /1 with no sign-ups/
    assert_select "*", text: /1 shift with no sign-ups/
    assert_select "span.badge", { text: /All covered/, count: 0 }
  end

  test "the index says so when the year has no shifts" do
    get scheduling_flake_report_path(year: YEAR)

    assert_response :success
    assert_select "*", text: /No #{YEAR} shifts have started yet/
  end

  # A shift that has not begun is not a shift anyone failed to show for. Left
  # unbounded, the current year -- the default view -- reported its whole
  # future schedule as flakes.
  test "shifts that have not started yet are left out" do
    future = create_slot(@ood, begins: @now + 2.hours, ends: @now + 8.hours)
    PersonSlot.create!(person: @admin, slot: future)

    get scheduling_flake_report_path(year: YEAR)

    assert_response :success
    assert_select "*", text: /No #{YEAR} shifts have started yet/
  end

  test "drill-down links carry the requested year, not the current one" do
    past = create_slot(@ood, begins: Time.zone.local(YEAR - 1, 8, 26, 6, 0, 0),
                             ends: Time.zone.local(YEAR - 1, 8, 26, 18, 0, 0))
    PersonSlot.create!(person: @admin, slot: past)

    get scheduling_flake_report_path(year: YEAR - 1)

    assert_response :success
    assert_select "a[href=?]", position_path(year: YEAR - 1)
    assert_select "a[href=?]", position_path(year: YEAR), count: 0
  end

  # --- Position drill-down ------------------------------------------------

  test "the drill-down lists a flake and a rogue for the shift" do
    build_shift

    get position_path

    assert_response :success
    assert_select "span.badge", text: /Flake/
    assert_select "span.badge", text: /Rogue/
    # The flake was on duty elsewhere, so the row names that position.
    assert_select "td", text: /#{Regexp.escape(@mentor.title)}/
    # A closed timesheet states both ends -- present tense read as "still out".
    assert_select "td", text: /On duty .* to /
    # datetime_format hands back a <span>; interpolating it into a detail line
    # rather than joining it printed the markup on the page.
    assert_no_escaped_markup
  end

  test "a rogue row carries the duration of the shift they rangered" do
    build_shift

    get position_path

    assert_response :success
    assert_select "td", text: /12 hours 0 min/
  end

  # They rangered the shift; only the slot link is missing, so there is
  # nothing for the reader to chase.
  test "a sign-up on duty for this position without the shift link is not reported" do
    slot = create_slot(@ood, begins: @now - 6.hours, ends: @now + 6.hours)
    PersonSlot.create!(person: @admin, slot:)
    create_timesheet(@admin, @ood, on_duty: slot.begins, off_duty: slot.ends)

    get position_path

    assert_response :success
    assert_select "span.badge", { text: /Flake/, count: 0 }
    assert_select "*", text: /was covered by the people who signed up for it/
  end

  test "a flake with no timesheet at all says so" do
    slot = create_slot(@ood, begins: @now - 6.hours, ends: @now + 6.hours)
    PersonSlot.create!(person: @admin, slot:)

    get position_path

    assert_response :success
    assert_select "td", text: /No timesheet during this shift/
  end

  # The three counts are disjoint and add up to the shift total.
  test "the drill-down splits the shifts into flagged, unstaffed, and honored" do
    build_shift
    clean = create_slot(@ood, begins: @now - 20.hours, ends: @now - 16.hours)
    PersonSlot.create!(person: @admin, slot: clean)
    create_timesheet(@admin, @ood, on_duty: clean.begins, off_duty: clean.ends, slot: clean)
    create_slot(@ood, begins: @now - 30.hours, ends: @now - 26.hours)

    get position_path

    assert_response :success
    assert_select "*", text: /1 shift with a flake or a rogue/
    assert_select "*", text: /1 shift with no sign-ups/
    assert_select "*", text: /1 shift everyone honored/
  end

  test "a position whose shifts were all covered says so" do
    slot = create_slot(@ood, begins: @now - 6.hours, ends: @now + 6.hours)
    PersonSlot.create!(person: @admin, slot:)
    create_timesheet(@admin, @ood, on_duty: slot.begins, off_duty: slot.ends, slot:)

    get position_path

    assert_response :success
    assert_select "*", text: /was covered by the people who signed up for it/
  end

  test "a position with no shifts that year says so" do
    get position_path

    assert_response :success
    assert_select "*", text: /No #{YEAR} shifts of this position have started yet/
  end

  # The selector posts an action-less GET, so it has to stay on this position
  # rather than dropping the reader back to the index.
  test "the drill-down carries its own year selector" do
    build_shift

    get position_path

    assert_response :success
    assert_select "select#year-selector-compact option[selected][value=?]", YEAR.to_s
    # No action attribute: the GET goes back to this very URL, position and all.
    assert_select "form[data-controller=form][action]", count: 0
  end

  test "an unknown position goes back to the index" do
    get scheduling_flake_report_position_path(0, year: YEAR)

    assert_redirected_to scheduling_flake_report_path(year: YEAR)
  end

  test "callsigns link only for readers who can open person pages" do
    build_shift
    slot_editor = @outsider
    grant_role(slot_editor, Role::EDIT_SLOTS)
    sign_in_as(slot_editor)

    get position_path

    assert_response :success
    # Edit Slots may read the report but not /person/:id -- an unguarded
    # callsign_link would hand them a table of links that bounce to /me.
    assert_select "a", { text: @admin.callsign, count: 0 }
    assert_includes response.body, @admin.callsign
  end
end
