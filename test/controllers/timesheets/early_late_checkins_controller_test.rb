# frozen_string_literal: true

require "test_helper"

class Timesheets::EarlyLateCheckinsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include EscapedMarkupTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers
  include TrainingSlotTestHelper
  include DomIdTestHelper

  YEAR = 2031

  setup do
    Rails.cache.clear
    Current.reset

    @now = Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    travel_to @now

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")

    @admin = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)

    @position = positions(:ood_position)
    @other_position = positions(:mentor_lead)

    Setting.find_or_create_by!(name: Setting::SHIFT_CHECK_IN_EARLY_PERIOD).update!(value: "60")
    Setting.find_or_create_by!(name: Setting::SHIFT_CHECK_IN_LATE_PERIOD).update!(value: "30")

    @slot = create_slot(@position, begins: @now, ends: @now + 8.hours,
                        description: "Dawn patrol")

    sign_in_as(@admin)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  def check_in(on_duty, person: @event_manager, position: @position, via: nil)
    timesheet = Timesheet.create!(person:, position:, on_duty:,
                                  additional_notes: "test shift")
    if via
      TimesheetLog.create!(action: TimesheetLog::CREATED, person_id: person.id,
                           create_person_id: @admin.id, timesheet_id: timesheet.id,
                           data: { "via" => via }, year: YEAR, created_at: on_duty)
    end
    timesheet
  end

  def create_early(person: @event_manager) = check_in(@now - 90.minutes, person:)
  def create_late(person: @event_manager) = check_in(@now + 1.hour, person:)

  # Upstream's TimesheetPolicy::before grants Admin and Timesheet Management
  # every method on the policy; earlyLateCheckins() adds no one, so this page is
  # closed to the Event Management reader who may open every other /timesheets
  # report.
  test "admin and timesheet management may view the report" do
    timesheet_manager = @outsider
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)

    [@admin, timesheet_manager].each do |viewer|
      sign_in_as(viewer)
      get timesheets_early_late_checkins_path(year: YEAR)
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "event management is turned away from this report" do
    sign_in_as(@event_manager)

    get timesheets_early_late_checkins_path(year: YEAR)

    assert_redirected_to me_root_path
  end

  test "someone without the role is turned away" do
    sign_in_as(@outsider)

    get timesheets_early_late_checkins_path(year: YEAR)

    assert_redirected_to me_root_path
  end

  test "a year with every check-in inside its window says so" do
    get timesheets_early_late_checkins_path(year: YEAR)

    assert_response :success
    assert_select "*", text: /Every check-in in #{YEAR} landed inside its window/
  end

  test "the page names the limits it applied" do
    create_early

    get timesheets_early_late_checkins_path(year: YEAR)

    assert_select "*", text: /Early limit: 1 hour/
    assert_select "*", text: /Late limit: 30 mins/
  end

  # A blank limit switches its check off. Saying "no early check-in this year"
  # under a switched-off early check claims a clean year on the strength of a
  # measurement no one took.
  test "a switched-off limit says so rather than reading as a clean year" do
    Setting.find_or_create_by!(name: Setting::SHIFT_CHECK_IN_EARLY_PERIOD).update!(value: "0")
    create_late

    get timesheets_early_late_checkins_path(year: YEAR)

    assert_select "*", text: /Early limit: switched off/
    assert_select "*", text: /early check-in limit is switched off/
    assert_select "*", text: /No early check-in in #{YEAR}/, count: 0
  end

  # The empty page never renders the sections, so the empty state is the only
  # place left that can admit the early check never ran.
  test "a clean year under one switched-off limit does not claim every check-in was measured" do
    Setting.find_or_create_by!(name: Setting::SHIFT_CHECK_IN_EARLY_PERIOD).update!(value: "0")
    create_early # outside the early window, but nothing measured it

    get timesheets_early_late_checkins_path(year: YEAR)

    assert_select "*", text: /early check-in limit is switched off/
    assert_select "*", text: /\AEvery check-in in #{YEAR} landed inside its window\.\z/, count: 0
  end

  test "both limits switched off does not report a clean year" do
    Setting.find_or_create_by!(name: Setting::SHIFT_CHECK_IN_EARLY_PERIOD).update!(value: "0")
    Setting.find_or_create_by!(name: Setting::SHIFT_CHECK_IN_LATE_PERIOD).update!(value: "0")
    create_late

    get timesheets_early_late_checkins_path(year: YEAR)

    assert_select "*", text: /Both check-in limits are switched off/
    assert_select "*", text: /landed inside its window/, count: 0
  end

  test "an early check-in is listed with its ranger, position, shift, and distance" do
    create_early

    get timesheets_early_late_checkins_path(year: YEAR)

    assert_response :success
    assert_select "th", text: @event_manager.callsign
    assert_select "*", text: /#{Regexp.escape(@position.title)}/
    assert_select "*", text: /Dawn patrol/
    assert_select "*", text: /1:30/
    # datetime_format hands back a <span>; interpolating rather than rendering
    # it prints the markup on the page.
    assert_no_escaped_markup
  end

  # A position whose shifts are days apart produces real check-ins weeks early,
  # and "686:27" is not a span a reader can place.
  test "a distance past a day is said in days rather than in hours" do
    create_slot(@other_position, begins: @now + 20.days, ends: @now + 20.days + 8.hours)
    check_in(@now, position: @other_position)

    get timesheets_early_late_checkins_path(year: YEAR)

    assert_select "*", text: /20 days 0 hours/
    assert_select "*", text: /480:00/, count: 0
  end

  # The label is built by another helper module's map. Nothing else on this page
  # names a via, so without this the delegation could break and the suite would
  # not notice.
  test "a check-in made through the bulk uploader says so on the page" do
    check_in(@now - 90.minutes, via: TimesheetLog::VIA_BULK_UPLOAD)

    get timesheets_early_late_checkins_path(year: YEAR)

    assert_select "*", text: /bulk uploader/
  end

  test "a check-in made through a missing timesheet request says so in the export" do
    check_in(@now - 90.minutes, via: TimesheetLog::VIA_MISSING_ENTRY)

    get timesheets_early_late_checkins_path(year: YEAR, format: :csv)

    assert_match(/missing entry request/, response.body)
  end

  # Duplicate ids let Turbo silently strip form fields, and this page stacks a
  # hero year selector, a filter bar carrying its own year field, and two
  # disclosures.
  test "the page emits no duplicate DOM ids" do
    create_early
    create_late

    get timesheets_early_late_checkins_path(year: YEAR)

    assert_unique_dom_ids
  end

  test "each half is headed and counted separately" do
    create_early
    create_late

    get timesheets_early_late_checkins_path(year: YEAR)

    assert_select "*", text: /Early Check-Ins/
    assert_select "*", text: /Late Check-Ins/
  end

  # An empty half is the answer to "how bad was the early problem this year",
  # so it is drawn rather than dropped.
  test "a half with nothing in it says so rather than disappearing" do
    create_late

    get timesheets_early_late_checkins_path(year: YEAR)

    assert_select "*", text: /No early check-in in #{YEAR}/
  end

  test "the rollups count each ranger and each position" do
    create_early
    create_late

    get timesheets_early_late_checkins_path(year: YEAR)

    assert_select "*", text: /Totals by Ranger \(1\)/
    assert_select "*", text: /Totals by Position \(1\)/
  end

  # Whole-year totals under a narrowed table would be answering a question
  # no one asked.
  test "the rollups follow the position filter" do
    create_slot(@other_position, begins: @now, ends: @now + 8.hours)
    check_in(@now - 90.minutes, position: @other_position)
    create_late

    get timesheets_early_late_checkins_path(year: YEAR, position_id: @other_position.id)

    assert_select "*", text: /Totals by Position \(1\)/
    assert_select "*", text: /Totals by Ranger \(1\)/
  end

  # The select has to keep offering the positions the reader is not looking at,
  # or a filter could never be changed, only cleared.
  test "the filter select still offers every position of the year" do
    create_slot(@other_position, begins: @now, ends: @now + 8.hours)
    check_in(@now - 90.minutes, position: @other_position)
    create_late

    get timesheets_early_late_checkins_path(year: YEAR, position_id: @other_position.id)

    assert_select "option", text: "#{@position.title} (1)"
    assert_select "option", text: "#{@other_position.title} (1)"
  end

  test "the position filter narrows both halves" do
    other_slot = create_slot(@other_position, begins: @now, ends: @now + 8.hours)
    check_in(@now - 90.minutes, position: @other_position)
    create_late

    get timesheets_early_late_checkins_path(year: YEAR, position_id: @other_position.id)

    assert_response :success
    assert_select "*", text: /No late check-in matched these filters/
    assert_select "*", text: /#{other_slot.description}/
  end

  test "the callsign filter is a substring match and narrows both halves" do
    create_early(person: @admin)
    create_late

    # Lowercase and mid-callsign: a substring match, not a prefix, and not
    # case-sensitive -- no one types a callsign the way it is capitalised.
    get timesheets_early_late_checkins_path(year: YEAR, callsign: "estrang")

    assert_response :success
    assert_select "th", text: @admin.callsign
    assert_select "th", text: @event_manager.callsign, count: 0
    assert_select "*", text: /No late check-in matched these filters/
  end

  # The report's only name for a deleted ranger is the one the row prints, so
  # the rows no one can click through to have to be reachable by it.
  test "the callsign filter reaches a deleted ranger by the name the row prints" do
    timesheet = create_early
    timesheet.update_columns(person_id: 0)

    get timesheets_early_late_checkins_path(year: YEAR, callsign: "deleted")

    assert_response :success
    assert_select "th", text: "Deleted #0"
  end

  test "the via filter narrows to one check-in method" do
    check_in(@now - 90.minutes, via: TimesheetLog::VIA_MISSING_ENTRY)
    create_early(person: @admin)

    get timesheets_early_late_checkins_path(year: YEAR,
                                            via: TimesheetLog::VIA_MISSING_ENTRY)

    assert_response :success
    assert_select "th", text: @event_manager.callsign
    assert_select "th", text: @admin.callsign, count: 0
  end

  # A shift started at HQ writes no creation log, so its via is nil -- and a
  # blank value in the URL reads as "no filter" rather than "that one".
  test "the via filter can ask for the check-ins that carry no creation log" do
    check_in(@now - 90.minutes, via: TimesheetLog::VIA_MISSING_ENTRY)
    create_early(person: @admin)

    get timesheets_early_late_checkins_path(year: YEAR,
                                            via: EarlyLateCheckInReport::VIA_NONE)

    assert_response :success
    assert_select "th", text: @admin.callsign
    assert_select "th", text: @event_manager.callsign, count: 0
  end

  # The select has to keep offering the methods the reader is not looking at,
  # for the same reason the position select does.
  test "the via select still offers every method of the year with its count" do
    check_in(@now - 90.minutes, via: TimesheetLog::VIA_MISSING_ENTRY)
    create_early(person: @admin)

    get timesheets_early_late_checkins_path(year: YEAR,
                                            via: TimesheetLog::VIA_MISSING_ENTRY)

    assert_select "option", text: "Missing entry request (1)"
    assert_select "option", text: "Check in (1)"
  end

  # A method nothing was entered by is not offered, so it cannot be chosen --
  # and a stale bookmark naming one must not draw a chip claiming it narrowed
  # anything.
  test "a via nothing was entered by is ignored rather than emptying the page" do
    create_early

    get timesheets_early_late_checkins_path(year: YEAR,
                                            via: TimesheetLog::VIA_BULK_UPLOAD)

    assert_response :success
    assert_select "th", text: @event_manager.callsign
    assert_select "*", text: /Via: /, count: 0
  end

  # The tiles count what is on screen, like the rollups and the count in the
  # bar: three totals for the whole year under a narrowed table would be
  # answering a question no one asked.
  test "the stat boxes follow the filter" do
    check_in(@now - 90.minutes, via: TimesheetLog::VIA_MISSING_ENTRY)
    create_late
    create_early(person: @admin)

    get timesheets_early_late_checkins_path(year: YEAR)
    assert_select "div", text: "2Early Check-Ins"
    assert_select "div", text: "1Late Check-Ins"
    assert_select "div", text: "1Via Missing Entry Request"

    get timesheets_early_late_checkins_path(year: YEAR, callsign: @admin.callsign)
    assert_select "div", text: "1Early Check-Ins"
    assert_select "div", text: "0Late Check-Ins"
    assert_select "div", text: "0Via Missing Entry Request"
  end

  # The export is what is on screen, so every filter has to reach it -- not just
  # the one the link was first written for.
  test "the export link carries every applied filter" do
    create_early

    get timesheets_early_late_checkins_path(year: YEAR, callsign: "echelon",
                                            via: EarlyLateCheckInReport::VIA_NONE,
                                            position_id: @position.id)

    assert_select "a[href*='.csv'][href*='callsign=echelon'][href*='via=none']" \
                  "[href*='position_id=#{@position.id}']"
  end

  test "the export follows the callsign and via filters" do
    check_in(@now - 90.minutes, via: TimesheetLog::VIA_MISSING_ENTRY)
    create_early(person: @admin)

    get timesheets_early_late_checkins_path(year: YEAR, format: :csv,
                                            via: TimesheetLog::VIA_MISSING_ENTRY)

    rows = response.body.split("\n")

    assert_equal 2, rows.size
    assert_match(/\A#{@event_manager.callsign},/, rows[1])
  end

  test "a position that flagged no one is ignored rather than emptying the page" do
    create_early

    get timesheets_early_late_checkins_path(year: YEAR, position_id: @other_position.id)

    assert_response :success
    assert_select "th", text: @event_manager.callsign
  end

  test "the year selector picks a different year and the page follows" do
    create_slot(@position, begins: Time.zone.local(YEAR - 1, 8, 26, 12, 0, 0),
                ends: Time.zone.local(YEAR - 1, 8, 26, 20, 0, 0))
    check_in(Time.zone.local(YEAR - 1, 8, 26, 10, 30, 0))

    get timesheets_early_late_checkins_path(year: YEAR)
    assert_select "*", text: /Every check-in in #{YEAR} landed inside its window/

    get timesheets_early_late_checkins_path(year: YEAR - 1)
    assert_select "th", text: @event_manager.callsign
  end

  test "the export carries upstream's columns in check-in order" do
    create_late
    create_early

    get timesheets_early_late_checkins_path(year: YEAR, format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/filename="#{YEAR}-early-late-checkins.csv"/, response.headers["Content-Disposition"])

    rows = response.body.split("\n")
    assert_equal "Callsign,Position,On Duty,Via,Type,By (minutes),Shift Start,Shift Description",
                 rows.first
    # Check-in order, not the page's worst-first: the export is the audit trail
    # of the year, read top to bottom.
    assert_match(/,early,90,/, rows[1])
    assert_match(/,late,60,/, rows[2])
    assert_match(/check in/, rows[1])
    # The wall clock the column stores, which is the one the page shows.
    # Converting to the host's zone or to Time.zone's offset would export a
    # different hour than the row the reader is looking at.
    assert_match(/,#{(@now - 90.minutes).strftime("%FT%T")},/, rows[1])
    assert_match(/,#{@now.strftime("%FT%T")},/, rows[1])
  end

  # The export link has to carry the filter, or the page and the file it offers
  # disagree about what is being exported.
  test "the export link carries the position filter" do
    create_early

    get timesheets_early_late_checkins_path(year: YEAR, position_id: @position.id)

    assert_select "a[href*='.csv'][href*='position_id=#{@position.id}']"
  end

  test "the export follows the position filter" do
    create_slot(@other_position, begins: @now, ends: @now + 8.hours)
    check_in(@now - 90.minutes, position: @other_position)
    create_late

    get timesheets_early_late_checkins_path(year: YEAR, position_id: @other_position.id,
                                            format: :csv)

    assert_equal 2, response.body.split("\n").size
    assert_match(/#{Regexp.escape(@other_position.title)}/, response.body)
  end
end
