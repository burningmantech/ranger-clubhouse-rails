# frozen_string_literal: true

require "test_helper"

class Scheduling::ShiftDropReportControllerTest < ActionDispatch::IntegrationTest
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
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")

    @admin = person(:active_ranger)
    @timesheet_manager = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@timesheet_manager, Role::TIMESHEET_MANAGEMENT)

    @ood = positions(:ood_position)
    @slot = create_slot(@ood, begins: @now + 20.hours, ends: @now + 26.hours,
                              description: "Graveyard")

    sign_in_as(@admin)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  # ActionLog.record stamps Current.time, and every case here turns on the exact
  # instant the removal was logged, so the rows are built directly.
  def log_drop(person, slot, at:, slot_id: slot&.id)
    ActionLog.create!(event: "person-slot-remove", message: "removed",
                      target_person_id: person.id, data: { "slot_id" => slot_id },
                      created_at: at)
  end

  # response.body is not a witness for a callsign: _top_menu renders "Hello
  # <callsign>" for the signed-in user on every authenticated page, so asserting
  # on the body passed whether or not the row rendered -- including for the
  # string-slot_id case, whose whole point is that the row would otherwise
  # vanish. The drop rows are th[scope=row] inside the shift tables.
  def assert_drop_row(person)
    assert_select "th[scope=row]", text: /#{Regexp.escape(person.callsign)}/, minimum: 1
  end

  def assert_no_drop_row(person)
    assert_select "th[scope=row]", text: /#{Regexp.escape(person.callsign)}/, count: 0
  end

  def index_path(year: YEAR, **options) = scheduling_shift_drop_report_path(year:, **options)

  def position_path(year: YEAR, **options)
    scheduling_shift_drop_report_position_path(@ood.id, year:, **options)
  end

  # --- Authorization ------------------------------------------------------

  # Upstream TimesheetPolicy: before admits Admin and Timesheet Management,
  # shiftDropReport() admits Event Management.
  test "admin, timesheet management, and event management may all view the report" do
    event_manager = @outsider
    grant_role(event_manager, Role::EVENT_MANAGEMENT)

    [@admin, @timesheet_manager, event_manager].each do |viewer|
      sign_in_as(viewer)
      get index_path
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  # The flake report next door admits Edit Slots; this one hangs off the
  # timesheet policy, which never has.
  test "edit slots is not admitted, unlike the flake report beside it" do
    grant_role(@outsider, Role::EDIT_SLOTS)
    sign_in_as(@outsider)

    get index_path
    assert_redirected_to me_root_path

    get position_path
    assert_redirected_to me_root_path
  end

  test "someone without any of the roles is turned away from both pages" do
    sign_in_as(@outsider)

    get index_path
    assert_redirected_to me_root_path

    get position_path
    assert_redirected_to me_root_path
  end

  # --- The window ---------------------------------------------------------

  test "a drop inside the window is reported and one before it is not" do
    log_drop(@admin, @slot, at: @slot.begins - 3.hours)
    log_drop(@outsider, @slot, at: @slot.begins - 20.hours)

    get position_path

    assert_response :success
    assert_drop_row(@admin)
    assert_no_drop_row(@outsider)
  end

  # Upstream's BETWEEN takes both ends, so the drop logged at exactly the
  # window's edge counts.
  test "a drop at exactly the window edge counts, and one after the start does not" do
    log_drop(@admin, @slot, at: @slot.begins - 12.hours)
    log_drop(@outsider, @slot, at: @slot.begins + 1.minute)

    get position_path

    assert_response :success
    assert_drop_row(@admin)
    assert_no_drop_row(@outsider)
  end

  # Two shifts, so the SQL pre-filter -- bounded by the earliest begins minus
  # the window and the latest begins -- is WIDER than either shift's own window,
  # and the per-slot test in Ruby is the only thing rejecting these two. With a
  # single shift in scope the two bounds coincide and deleting that test
  # entirely still passes every other case here.
  test "a drop outside its own shift's window is rejected inside the report's span" do
    later = create_slot(@ood, begins: @now + 60.hours, ends: @now + 66.hours)
    # After its own shift began, but well before the span's end.
    log_drop(@outsider, @slot, at: @slot.begins + 30.minutes)
    # Inside the span's start, but 30 hours before its own shift.
    log_drop(@timesheet_manager, later, at: later.begins - 30.hours)
    log_drop(@admin, later, at: later.begins - 2.hours)

    get position_path

    assert_response :success
    assert_drop_row(@admin)
    assert_no_drop_row(@outsider)
    assert_no_drop_row(@timesheet_manager)
  end

  test "widening the window pulls in the earlier drop" do
    log_drop(@outsider, @slot, at: @slot.begins - 20.hours)

    get position_path(hours: 24)

    assert_response :success
    assert_drop_row(@outsider)
  end

  # A window the select never offers is the default rather than an error page.
  test "an unoffered window falls back to the default rather than failing" do
    log_drop(@admin, @slot, at: @slot.begins - 3.hours)
    log_drop(@outsider, @slot, at: @slot.begins - 20.hours)

    get index_path(hours: 999)

    assert_response :success
    assert_select "*", text: /within 12 hours of shift start/
    assert_select "option[selected][value=?]", "12"
  end

  # --- What is in scope ---------------------------------------------------

  test "a drop on another year's shift or an inactive one is left out" do
    other_year = create_slot(@ood, begins: Time.zone.local(YEAR - 1, 8, 26, 8, 0, 0),
                                   ends: Time.zone.local(YEAR - 1, 8, 26, 14, 0, 0))
    inactive = create_slot(@ood, begins: @now + 30.hours, ends: @now + 36.hours,
                                 active: false)
    log_drop(@outsider, other_year, at: other_year.begins - 1.hour)
    log_drop(@outsider, inactive, at: inactive.begins - 1.hour)

    get index_path

    assert_response :success
    assert_select "*", text: /No #{YEAR} shift lost anyone within 12 hours/
  end

  # A removal whose log names no shift, or one whose shift has since been
  # deleted, cannot be placed and must not take the page down with it.
  test "a removal naming no shift is skipped rather than raising" do
    log_drop(@outsider, nil, at: @slot.begins - 1.hour, slot_id: nil)
    log_drop(@outsider, nil, at: @slot.begins - 1.hour, slot_id: 0)
    log_drop(@admin, @slot, at: @slot.begins - 1.hour)

    get position_path

    assert_response :success
    assert_drop_row(@admin)
  end

  # A non-scalar id cannot be coerced and must be skipped like any other
  # unusable one -- the whole year is scanned in a single pass, so one bad row
  # raising takes down the index, every drill-down, and the export.
  test "a removal whose slot id is not a scalar is skipped rather than raising" do
    log_drop(@outsider, nil, at: @slot.begins - 1.hour, slot_id: ["1"])
    log_drop(@timesheet_manager, nil, at: @slot.begins - 1.hour, slot_id: { "id" => 1 })
    log_drop(@admin, @slot, at: @slot.begins - 1.hour)

    get position_path

    assert_response :success
    assert_drop_row(@admin)
  end

  # The Laravel writers pass the id straight from a request parameter, so it
  # lands in the JSON as a string often enough to matter: every one of 2019's
  # removals stores it that way.
  test "a slot id recorded as a string still matches its shift" do
    log_drop(@admin, @slot, at: @slot.begins - 1.hour, slot_id: @slot.id.to_s)

    get position_path

    assert_response :success
    assert_drop_row(@admin)
  end

  # A shift starting tomorrow that just lost someone is exactly the row this
  # report exists to show -- unlike the flake report, there is no "already
  # started" bound. @slot itself begins in the future.
  test "shifts that have not started yet are in scope" do
    soon = create_slot(@ood, begins: @now + 2.hours, ends: @now + 8.hours)
    log_drop(@admin, soon, at: @now - 1.hour)

    get index_path

    assert_response :success
    assert_select "a[href=?]", position_path(hours: 12), text: /#{Regexp.escape(@ood.title)}/
  end

  # --- Index --------------------------------------------------------------

  test "the index counts the position's drops and shifts" do
    second = create_slot(@ood, begins: @now + 40.hours, ends: @now + 46.hours)
    log_drop(@admin, @slot, at: @slot.begins - 3.hours)
    log_drop(@outsider, @slot, at: @slot.begins - 4.hours)
    log_drop(@admin, second, at: second.begins - 5.hours)

    get index_path

    assert_response :success
    assert_select "*", text: /3 drops/
    assert_select "*", text: /2 shifts/
  end

  # The badge is the whole triage signal of the page.
  test "only the drops with no time left to backfill are badged" do
    log_drop(@admin, @slot, at: @slot.begins - 30.minutes)
    log_drop(@outsider, @slot, at: @slot.begins - 8.hours)

    get index_path

    assert_response :success
    assert_select "span.badge", text: /1 within 2 hours/
  end

  # Asked for one hour, every drop is inside two and the badge would say nothing.
  test "no urgency badge when the window is already inside the threshold" do
    log_drop(@admin, @slot, at: @slot.begins - 30.minutes)

    get index_path(hours: 1)

    assert_response :success
    assert_select "span.badge", { text: /within 2 hours/, count: 0 }
  end

  # The same rule, on the page the index links to: at a one-hour window every
  # row qualifies, and marking all of them red distinguishes nothing.
  test "no urgency badge on the drill-down when the window is inside the threshold" do
    log_drop(@admin, @slot, at: @slot.begins - 30.minutes)

    get position_path(hours: 1)

    assert_response :success
    assert_drop_row(@admin)
    assert_select "td span.badge", count: 0

    get position_path(hours: 12)

    assert_response :success
    assert_select "td span.badge", minimum: 1
  end

  test "the index separates no drops from no shifts at all" do
    get index_path

    assert_response :success
    assert_select "*", text: /No #{YEAR} shift lost anyone within 12 hours/

    get index_path(year: YEAR - 2)

    assert_response :success
    assert_select "*", text: /No shifts have been scheduled for #{YEAR - 2}/
  end

  # At the widest window the select carries, "widen the window" is the only
  # action the empty page suggests and the one the reader cannot take.
  test "the empty state suggests widening only when there is somewhere to widen to" do
    get index_path

    assert_response :success
    assert_select "*", text: /Widen the window/

    get index_path(hours: 48)

    assert_response :success
    assert_select "*", { text: /Widen the window/, count: 0 }
    assert_select "*", text: /No #{YEAR} shift lost anyone within 48 hours/

    get position_path(hours: 48)

    assert_response :success
    assert_select "*", { text: /Widen the window/, count: 0 }
  end

  # The window is half the question, so following any link has to keep asking it.
  test "drill-down and export links carry both the year and the window" do
    log_drop(@admin, @slot, at: @slot.begins - 20.hours)

    get index_path(hours: 24)

    assert_response :success
    assert_select "a[href=?]", position_path(hours: 24)
    assert_select "a[href=?]", index_path(hours: 24, format: :csv)
  end

  # A chip that removes the default window would have nowhere to land.
  test "the window draws a chip only once it differs from the default" do
    get index_path

    assert_response :success
    assert_select "a", { text: /Dropped Within:/, count: 0 }

    get index_path(hours: 24)

    assert_response :success
    # Removing it returns to the default window, not to "no window" -- which is
    # not a thing this report has.
    assert_select "a[href=?]", index_path, text: /Dropped Within: 24 hours of start/

    get position_path(hours: 24)

    assert_response :success
    assert_select "a[href=?]", position_path, text: /Dropped Within: 24 hours of start/
  end

  # --- Position drill-down ------------------------------------------------

  test "the drill-down groups the drops under their shift and names the notice" do
    log_drop(@admin, @slot, at: @slot.begins - 90.minutes)

    get position_path

    assert_response :success
    assert_select "*", text: /Graveyard/
    assert_select "td", text: /1 hour 30 min/
    # datetime_format hands back a <span>; interpolating rather than joining it
    # prints the markup on the page.
    assert_no_escaped_markup
  end

  test "the drill-down counts drops, shifts, and the rangers behind them" do
    log_drop(@admin, @slot, at: @slot.begins - 2.hours)
    log_drop(@admin, @slot, at: @slot.begins - 3.hours)
    log_drop(@outsider, @slot, at: @slot.begins - 4.hours)

    get position_path

    assert_response :success
    # Three drops from two people: the gap between the two numbers is the point.
    # ui_stat_box renders value and label as sibling divs, so the container's
    # text runs them together.
    assert_select "*", text: /3 drops/
    assert_select "div", text: /2Rangers/
  end

  test "the drill-down separates no drops from no shifts at all" do
    get position_path

    assert_response :success
    assert_select "*", text: /No #{YEAR} shift of this position lost anyone/

    get position_path(year: YEAR - 2)

    assert_response :success
    assert_select "*", text: /No #{YEAR - 2} shifts have been scheduled for this position/
  end

  test "an unknown position goes back to the index" do
    get scheduling_shift_drop_report_position_path(0, year: YEAR, hours: 24)

    assert_redirected_to index_path(hours: 24)
  end

  # The selector posts an action-less GET, so it has to stay on this position
  # and keep the window with it.
  test "the drill-down year selector keeps the position and the window" do
    log_drop(@admin, @slot, at: @slot.begins - 20.hours)

    get position_path(hours: 24)

    assert_response :success
    assert_select "select#year-selector-compact option[selected][value=?]", YEAR.to_s
    # hero_panel renders the selector twice (compact and full), so both copies
    # carry the hidden field and an unscoped assertion would pass on one alone.
    assert_select "form[data-controller=form] input[name=hours][value='24']", count: 2
  end

  test "callsigns link only for readers who can open person pages" do
    log_drop(@admin, @slot, at: @slot.begins - 1.hour)
    sign_in_as(@timesheet_manager)

    get position_path

    assert_response :success
    # Timesheet Management may read this report but not /person/:id -- an
    # unguarded callsign_link would hand them links that bounce to /me.
    assert_select "a", { text: @admin.callsign, count: 0 }
    # Scoped to the row: @timesheet_manager is the signed-in user here, so a
    # body-wide check would pass on the navbar greeting instead.
    assert_drop_row(@admin)
  end

  # --- Export -------------------------------------------------------------

  test "the export carries every position and names each callsign once" do
    mentor = positions(:mentor_lead)
    other = create_slot(mentor, begins: @now + 30.hours, ends: @now + 36.hours,
                                description: "Mentor shift")
    log_drop(@admin, @slot, at: @slot.begins - 90.minutes)
    log_drop(@outsider, other, at: other.begins - 1.hour)

    get index_path(format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    lines = response.body.lines
    # Exact, not assert_includes: "Shift" is a substring of "Shift Start", so a
    # containment check passed even with the description column deleted.
    # (Upstream also defines Callsign twice, duplicating that column.)
    assert_equal ["Position", "Shift Start", "Shift", "Callsign", "Dropped At", "Hours Before Start"],
                 lines.first.strip.split(",")
    assert_equal 3, lines.size, "the header plus one drop from each position"

    row = lines.detect { |line| line.include?(@ood.title) }
    assert_includes row, "Graveyard"
    assert_includes row, @admin.callsign
    # Hours stay decimal in the export, as upstream has them.
    assert_includes row, "1.5"

    # The export spans positions and is ordered by title, which one position
    # alone could never show.
    assert(lines.any? { |line| line.include?(mentor.title) }, "the other position is exported too")
    titles = lines.drop(1).map { |line| line.split(",").first }
    assert_equal titles.sort_by(&:downcase), titles, "rows are ordered by position title"
  end

  # New York's 09:00 is 06:00 here, so a removal logged at 05:00 here shows and
  # exports at 08:00 New York time: an hour's notice, on the heading's clock.
  test "a shift in another zone shows and exports its drop on its own clock" do
    new_york = create_slot(@ood, begins: Time.zone.local(YEAR, 8, 27, 9, 0, 0),
                                 ends: Time.zone.local(YEAR, 8, 27, 15, 0, 0),
                                 description: "Brooklyn", timezone: "America/New_York")
    log_drop(@outsider, new_york, at: Time.zone.local(YEAR, 8, 27, 5, 0, 0))

    get position_path
    assert_includes response.body, ">Wed Aug 27, #{YEAR} @ 08:00 (EDT)</span>"

    get index_path(format: :csv)
    row = response.body.lines.detect { |line| line.include?("Brooklyn") }
    assert_includes row, "#{YEAR}-08-27T09:00:00-04:00,Brooklyn,"
    assert_includes row, ",#{YEAR}-08-27T08:00:00-04:00,1.0"
  end

  test "the export honors the window it was asked for" do
    log_drop(@admin, @slot, at: @slot.begins - 20.hours)

    get index_path(format: :csv)
    assert_equal 1, response.body.lines.size, "only the header for the default window"

    get index_path(hours: 24, format: :csv)
    assert_equal 2, response.body.lines.size
  end

  # Two windows are two different reports; sharing one filename hands the reader
  # two files with the same name and no way to tell which is which.
  test "the export filename carries the window as well as the year" do
    get index_path(format: :csv)
    assert_equal %(attachment; filename="#{YEAR}-shift-drops-within-12h.csv"; ) +
                 %(filename*=UTF-8''#{YEAR}-shift-drops-within-12h.csv),
                 response.headers["Content-Disposition"]

    get index_path(hours: 48, format: :csv)
    assert_includes response.headers["Content-Disposition"], "#{YEAR}-shift-drops-within-48h.csv"
  end
end
