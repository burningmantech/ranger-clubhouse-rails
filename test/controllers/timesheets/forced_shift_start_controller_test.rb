# frozen_string_literal: true

require "test_helper"

class Timesheets::ForcedShiftStartControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
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
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")

    @admin = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)

    @position = positions(:ood_position)

    sign_in_as(@admin)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  def create_forced(person: @event_manager, on_duty: @now, reason: "signed on paper at HQ",
                    blockers: nil, position: @position, forced_by: @admin)
    timesheet = Timesheet.create!(person:, position:, on_duty:,
                                  was_signin_forced: true, signin_force_reason: reason,
                                  additional_notes: "test shift")
    if blockers
      TimesheetLog.create!(action: TimesheetLog::SIGNON, person_id: person.id,
                           create_person_id: forced_by.id, timesheet_id: timesheet.id,
                           data: { "forced" => true, "blockers" => blockers },
                           year: YEAR, created_at: on_duty)
    end
    timesheet
  end

  # Two forced starts that differ on every filterable field, so each filter can
  # be shown to narrow to exactly one of them.
  def create_two_forced
    @other_person = person(:auditor_ranger)
    @other_forcer = person(:retired_ranger)
    @other_position = positions(:training_lead)

    create_forced(blockers: [{ "blocker" => Timesheet::BLOCKED_TOO_LATE, "distance" => 130,
                               "cutoff" => 15,
                               "slot" => { "begins" => "#{YEAR}-08-26 09:50:00" } }])
    create_forced(person: @other_person, position: @other_position,
                  forced_by: @other_forcer,
                  blockers: [{ "blocker" => Timesheet::BLOCKED_NOT_TRAINED }])
  end

  # Upstream's TimesheetPolicy::before grants Admin and Timesheet Management
  # every method on the policy; forcedSigninsReport() adds Event Management.
  test "admin, event management, and timesheet management may all view the report" do
    timesheet_manager = @outsider
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)

    [@admin, @event_manager, timesheet_manager].each do |viewer|
      sign_in_as(viewer)
      get timesheets_forced_shift_start_path(year: YEAR)
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "someone without the role is turned away" do
    sign_in_as(@outsider)

    get timesheets_forced_shift_start_path(year: YEAR)

    assert_redirected_to me_root_path
  end

  test "a year with nothing forced says so" do
    get timesheets_forced_shift_start_path(year: YEAR)

    assert_response :success
    assert_select "*", text: /No shift start was forced in #{YEAR}/
  end

  test "the table names the ranger, the forcer, the blockers, and the reason" do
    create_forced(blockers: [{ "blocker" => Timesheet::BLOCKED_TOO_LATE,
                               "distance" => 130, "cutoff" => 15,
                               "slot" => { "begins" => "#{YEAR}-08-26 09:50:00" } }])

    get timesheets_forced_shift_start_path(year: YEAR)

    assert_response :success
    assert_select "th", text: @event_manager.callsign
    assert_select "*", text: /#{@admin.callsign}/
    assert_select "*", text: /2 hours 10 mins after the 09:50 start/
    assert_select "*", text: /signed on paper at HQ/
    # datetime_format hands back a <span>; interpolating rather than rendering
    # it prints the markup on the page.
    assert_no_escaped_markup
  end

  test "a missing reason and a missing audit log each say what is not known" do
    create_forced(reason: nil)

    get timesheets_forced_shift_start_path(year: YEAR)

    assert_select "*", text: /No reason given/
    assert_select "*", text: /Not recorded/
  end

  test "the year selector picks a different year and the page follows" do
    create_forced(on_duty: Time.zone.local(YEAR - 1, 8, 26, 12, 0, 0))

    get timesheets_forced_shift_start_path(year: YEAR)
    assert_select "*", text: /No shift start was forced in #{YEAR}/

    get timesheets_forced_shift_start_path(year: YEAR - 1)
    assert_select "th", text: @event_manager.callsign
  end

  test "the export carries upstream's columns and the blockers one per line" do
    create_forced(blockers: [{ "blocker" => Timesheet::BLOCKED_NO_EMPLOYEE_ID },
                             { "blocker" => Timesheet::BLOCKED_UNSIGNED_SANDMAN_AFFIDAVIT }])

    get timesheets_forced_shift_start_path(year: YEAR, format: :csv)

    assert_response :success
    assert_equal "text/csv; charset=utf-8", response.media_type + "; charset=utf-8"
    assert_match(/attachment; filename="#{YEAR}-forced-shift-starts.csv"/, response.headers["Content-Disposition"])
    assert_includes response.body, "Person,Position,Shift Start,Forced By,Blockers,Reason"
    assert_includes response.body, "\"No employee id on file for a paid position\n" \
                                   "Sandman Affidavit not signed\""
  end

  test "each filter narrows the table to the matching forced start" do
    create_two_forced

    { person_id: [@other_person.id, "Person: #{@other_person.callsign}"],
      forced_by_id: [@other_forcer.id, "Forced By: #{@other_forcer.callsign}"],
      position_id: [@other_position.id, "Position: #{@other_position.title}"],
      blocker: [Timesheet::BLOCKED_NOT_TRAINED,
                "Blocked Reason: Has not completed training"] }.each do |filter, (value, chip)|
      get timesheets_forced_shift_start_path(year: YEAR, filter => value)

      assert_response :success
      assert_select "th", text: @other_person.callsign, count: 1,
                    message: "#{filter} should keep the matching row"
      assert_select "th", text: @event_manager.callsign, count: 0,
                    message: "#{filter} should drop the other row"
      assert_select "*", text: /Showing 1 of 2 forced starts/
      # The chip names what the select named, and its remove link drops only it.
      assert_select "a[aria-label=?]", "Remove filter: #{chip}"
    end
  end

  # Every select offers only values the year holds, so a single choice always
  # returns something -- but the four combine, and a combination need not.
  test "filters combine, and a combination matching nothing says so" do
    create_two_forced

    get timesheets_forced_shift_start_path(year: YEAR, person_id: @other_person.id,
                                           position_id: @position.id)

    assert_response :success
    assert_select "*", text: /No forced start in #{YEAR} matches all of those filters/
    assert_select "*", text: /Showing 0 of 2 forced starts/
  end

  # A stale bookmark or a hand-edited URL must not draw a chip claiming a filter
  # that narrowed nothing, and `?person_id[]=1` must not reach the chip builder.
  test "a filter value the year does not hold is ignored" do
    create_two_forced

    [{ person_id: 999_999 }, { blocker: "no-such-blocker" }, { position_id: ["1"] }].each do |bad|
      get timesheets_forced_shift_start_path(year: YEAR, **bad)

      assert_response :success
      assert_select "*", text: /Showing 2 of 2 forced starts/, message: bad.inspect
    end
  end

  test "the export carries the filters the page is showing" do
    create_two_forced

    get timesheets_forced_shift_start_path(year: YEAR, format: :csv,
                                           blocker: Timesheet::BLOCKED_NOT_TRAINED)

    assert_response :success
    assert_includes response.body, @other_person.callsign
    assert_not_includes response.body, @event_manager.callsign
  end

  # The schema carries no FK on timesheet_log.create_person_id. An empty cell
  # would read as "no one forced this", which is what a start with no log says.
  test "the export names a deleted forcer rather than leaving the cell empty" do
    timesheet = create_forced
    TimesheetLog.create!(action: TimesheetLog::SIGNON, person_id: timesheet.person_id,
                         create_person_id: 999_999, timesheet_id: timesheet.id,
                         data: { "forced" => true, "blockers" => [] },
                         year: YEAR, created_at: @now)

    get timesheets_forced_shift_start_path(year: YEAR)
    assert_select "*", text: /Deleted #999999/

    get timesheets_forced_shift_start_path(year: YEAR, format: :csv)
    assert_includes response.body, "Deleted #999999"
  end
end
