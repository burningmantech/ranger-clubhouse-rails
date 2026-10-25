# frozen_string_literal: true

require "test_helper"

class ShiftOperations::PayrollExportControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ReportCardTestHelper     # assert_report_card / card_answer
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2025

  setup do
    Rails.cache.clear
    Current.reset

    @now = Time.zone.local(YEAR, 9, 3, 12, 0, 0)
    travel_to @now

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::PAYROLL, "Payroll")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")

    @admin = person(:active_ranger)
    @clerk = person(:echelon_ranger)
    @ranger = person(:auditor_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@clerk, Role::PAYROLL)

    @admin.update!(employee_id: "E-1001")
    @ranger.update!(employee_id: "E-2002")

    @position = Position.create!(title: "Payroll Dirt", active: true, paycode: "DIRT")

    sign_in_as(@clerk)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  def create_entry(on_duty:, off_duty: nil, who: nil, position: @position,
                   review_status: Timesheet::STATUS_UNVERIFIED)
    Timesheet.create!(person: who || @ranger, position:, on_duty:, off_duty:, review_status:,
                      additional_notes: "test shift")
  end

  def at(hour, minute = 0, day: 1)
    Time.zone.local(YEAR, 9, day, hour, minute, 0)
  end

  def query(overrides = {})
    { "payroll" => { start_time: at(0).strftime("%Y-%m-%dT%H:%M"),
                     end_time: at(23, 59).strftime("%Y-%m-%dT%H:%M"),
                     break_after: 0,
                     break_duration: 60,
                     position_ids: [@position.id] }.merge(overrides) }
  end

  def csv_lines(body) = body.split("\n")

  # ---------------------------------------------------------------- access

  test "payroll may open the page" do
    get shift_operations_payroll_export_path

    assert_response :success
  end

  test "admin may open the page" do
    sign_in_as(@admin)

    get shift_operations_payroll_export_path

    assert_response :success
  end

  # Timesheet Management reads every other timesheet report in the application,
  # which makes it the plausible-but-wrong gate for this one.
  test "timesheet management is turned away" do
    grant_role(@ranger, Role::TIMESHEET_MANAGEMENT)
    sign_in_as(@ranger)

    get shift_operations_payroll_export_path

    assert_redirected_to me_root_path
  end

  test "a ranger with no payroll role is turned away from a download too" do
    sign_in_as(@ranger)

    get shift_operations_payroll_export_path(query.merge(format: :csv))

    assert_redirected_to me_root_path
  end

  # ----------------------------------------------------------------- form

  test "the first visit offers the parameters and runs nothing" do
    create_entry(on_duty: at(9), off_duty: at(12))

    get shift_operations_payroll_export_path

    assert_response :success
    assert_select "form"
    assert_select "#payroll-person-#{@ranger.id}", false
  end

  test "the default window is the week ending on the most recent sunday" do
    get shift_operations_payroll_export_path

    # 2025-09-03 is a Wednesday; the week payroll is being run for ran from
    # Sunday the 24th to Sunday the 31st.
    assert_select "input[name=?][value=?]", "payroll[start_time]", "2025-08-24T00:00"
    assert_select "input[name=?][value=?]", "payroll[end_time]", "2025-08-31T00:00"
  end

  test "an end before the start is refused and nothing is reported" do
    create_entry(on_duty: at(9), off_duty: at(12))

    get shift_operations_payroll_export_path(query(start_time: at(20).strftime("%Y-%m-%dT%H:%M"),
                                                   end_time: at(8).strftime("%Y-%m-%dT%H:%M")))

    assert_response :success
    assert_select "#payroll-person-#{@ranger.id}", false
    assert_match(/has to come after the start/, response.body)
  end

  test "asking for no positions is refused" do
    get shift_operations_payroll_export_path(query(position_ids: []))

    assert_response :success
    assert_match(/Choose at least one position/, response.body)
  end

  # Kept, "0" would count as a position chosen and then find nothing.
  test "position ids that are not ids count as none chosen" do
    get shift_operations_payroll_export_path(query(position_ids: ["abc", "", "7x", "0"]))

    assert_response :success
    assert_match(/Choose at least one position/, response.body)
  end

  # This page is meant to be bookmarked and re-sent, so a mangled address is an
  # ordinary way to arrive, not only a crafted one.
  test "a scope that is not a set of parameters does not fail the page" do
    ["payroll=whatever", "payroll[]=1"].each do |junk|
      get "/shift-operations/payroll-export?#{junk}"

      assert_response :success, "#{junk} should fall back to the default form"
    end
  end

  test "a pay period longer than the cap is refused" do
    get shift_operations_payroll_export_path(
      query(start_time: at(0).strftime("%Y-%m-%dT%H:%M"),
            end_time: (at(0) + 120.days).strftime("%Y-%m-%dT%H:%M"))
    )

    assert_response :success
    assert_match(/cannot be longer than/, response.body)
  end

  # The ids ride in the query string, so an old bookmark can name a position
  # that has since lost its paycode -- whose hours have nothing to book against.
  test "a position the page does not offer is ignored" do
    retired = Position.create!(title: "Payroll Retired", active: false, paycode: "OLD")
    create_entry(on_duty: at(9), off_duty: at(12), position: retired)

    get shift_operations_payroll_export_path(query(position_ids: [@position.id, retired.id]))

    assert_response :success
    assert_match(/No timesheet entries were found/, response.body)
    # The picker's count arrives rendered, and the id the page does not offer ticks nothing.
    assert_select "[data-position-picker-target=count]",
                  text: "1 of #{css_select("[data-position-picker-target=checkbox]").size} selected"
  end

  # A break length off the list is refused rather than used. An integer
  # attribute turns anything unparseable into 0, and 0 would punch out to lunch
  # and back at the same instant; a bad break_after would silently mean no
  # breaks at all. The entry has to exist, or the absence proves nothing.
  test "a meal break length the page does not offer is refused" do
    create_entry(on_duty: at(6), off_duty: at(16))

    [-1, 0, 45, "abc"].each do |bad|
      get shift_operations_payroll_export_path(query(break_after: 4, break_duration: bad))

      assert_response :success
      assert_match(/offered meal break lengths/, response.body, "break_duration=#{bad}")
      assert_select "#payroll-person-#{@ranger.id}", false
    end
  end

  test "a meal break threshold the page does not offer is refused" do
    create_entry(on_duty: at(6), off_duty: at(16))

    ["abc", 3, 99].each do |bad|
      get shift_operations_payroll_export_path(query(break_after: bad))

      assert_response :success
      assert_match(/offered meal break thresholds/, response.body, "break_after=#{bad}")
    end
  end

  # Built from the narrowed report the picker collapses to whoever is already
  # chosen, and there is no way to move straight to anyone else.
  test "the person picker keeps offering everyone while one person is shown" do
    create_entry(on_duty: at(9), off_duty: at(12))
    create_entry(on_duty: at(9), off_duty: at(12), who: @admin)

    get shift_operations_payroll_export_path(query(person_id: @ranger.id))

    assert_select "#payroll-person-filter option[value=?]", @admin.id.to_s
    assert_select "#payroll-person-filter option[value=?]", @ranger.id.to_s
  end

  # ---------------------------------------------------------------- report

  test "a run lists a card per person with their hours" do
    create_entry(on_duty: at(9), off_duty: at(12))

    get shift_operations_payroll_export_path(query)

    assert_response :success
    assert_select "#payroll-person-#{@ranger.id}"
    assert_select "body", /3:00/
  end

  test "someone with no paycom id is named in the callout, not the cards" do
    @ranger.update!(employee_id: nil)
    create_entry(on_duty: at(9), off_duty: at(12))

    get shift_operations_payroll_export_path(query)

    assert_response :success
    # Scoped to the callout: the sidebar links "Missing Paycom Employee IDs" on
    # every Shift Operations page, so a match on the whole body would pass with
    # the callout gone.
    assert_select "[role=alert]", text: /Missing a Paycom Employee ID.*#{@ranger.callsign}/m
    assert_select "#payroll-person-#{@ranger.id}", false
  end

  test "a pay period with nothing in it says so" do
    get shift_operations_payroll_export_path(query)

    assert_response :success
    assert_match(/No timesheet entries were found/, response.body)
  end

  # The card says which of the three exports payroll loads, by the labels on
  # their buttons, so it is offered only where those buttons are.
  test "the card names the files payroll loads, where there are files to export" do
    get shift_operations_payroll_export_path(query)

    assert_match(/No timesheet entries were found/, response.body)
    assert_report_card count: 0

    create_entry(on_duty: at(9), off_duty: at(12))
    get shift_operations_payroll_export_path(query)

    assert_report_card
    assert_match(/are what payroll loads/, card_answer("Which files does payroll load?"))
  end

  test "the person filter narrows the page to one card" do
    create_entry(on_duty: at(9), off_duty: at(12))
    create_entry(on_duty: at(9), off_duty: at(12), who: @admin)

    get shift_operations_payroll_export_path(query(person_id: @ranger.id))

    assert_select "#payroll-person-#{@ranger.id}"
    assert_select "#payroll-person-#{@admin.id}", false
  end

  # ---------------------------------------------------------------- exports

  test "the adjusted file punches a whole shift in and out once" do
    create_entry(on_duty: at(9), off_duty: at(12))

    get shift_operations_payroll_export_path(query.merge(format: :csv))

    assert_response :success
    assert_equal "text/csv", response.media_type
    lines = csv_lines(response.body)
    assert_equal 3, lines.size
    assert_match(/^E-2002,660,2025-09-01,09:00,ID,/, lines[1])
    assert_match(/^E-2002,,2025-09-01,12:00,OD,/, lines[2])
  end

  test "a shift cut for a meal break punches out to lunch and back" do
    create_entry(on_duty: at(6, 45), off_duty: at(15))

    get shift_operations_payroll_export_path(query(break_after: 4).merge(format: :csv))

    lines = csv_lines(response.body)
    assert_equal 5, lines.size
    assert_match(/2025-09-01,06:45,ID,/, lines[1])
    assert_match(/2025-09-01,10:45,OL,/, lines[2])
    assert_match(/2025-09-01,11:45,IL,/, lines[3])
    assert_match(/2025-09-01,15:00,OD,/, lines[4])
  end

  test "only the in punch carries the department, paycode and comment" do
    create_entry(on_duty: at(9), off_duty: at(12))

    get shift_operations_payroll_export_path(query.merge(format: :csv))

    in_row, out_row = csv_lines(response.body)[1..2]
    assert_match(/660/, in_row)
    assert_match(/DIRT/, in_row)
    assert_match(/#{@ranger.callsign} - Payroll Dirt/, in_row)
    assert_no_match(/660/, out_row)
    assert_no_match(/DIRT/, out_row)
  end

  test "the adjusted file clips a shift to the pay window" do
    create_entry(on_duty: at(6), off_duty: at(20))

    get shift_operations_payroll_export_path(
      query(start_time: at(8).strftime("%Y-%m-%dT%H:%M"),
            end_time: at(18).strftime("%Y-%m-%dT%H:%M")).merge(format: :csv)
    )

    lines = csv_lines(response.body)
    assert_match(/2025-09-01,08:00,ID,/, lines[1])
    assert_match(/2025-09-01,18:00,OD,/, lines[2])
  end

  test "the unadjusted file keeps the times as they were recorded" do
    create_entry(on_duty: at(6), off_duty: at(20))

    get shift_operations_payroll_export_path(
      query(start_time: at(8).strftime("%Y-%m-%dT%H:%M"),
            end_time: at(18).strftime("%Y-%m-%dT%H:%M")).merge(variant: "unadjusted", format: :csv)
    )

    lines = csv_lines(response.body)
    assert_equal 3, lines.size
    assert_match(/2025-09-01,06:00,ID,/, lines[1])
    assert_match(/2025-09-01,20:00,OD,/, lines[2])
  end

  test "the table file names its columns and one row per entry" do
    create_entry(on_duty: at(9), off_duty: at(12))

    get shift_operations_payroll_export_path(query.merge(variant: "table", format: :csv))

    lines = csv_lines(response.body)
    assert_equal 2, lines.size
    assert_match(/^Callsign,First Name,Last Name,Employee ID,Position,Paycode,Entry Status,/, lines[0])
    assert_match(/Unverified/, lines[1])
    assert_match(/3:00/, lines[1])
  end

  test "the without-ids file leaves the employee number empty" do
    @ranger.update!(employee_id: nil)
    create_entry(on_duty: at(9), off_duty: at(12))

    get shift_operations_payroll_export_path(query.merge(variant: "without-ids", format: :csv))

    lines = csv_lines(response.body)
    assert_equal 3, lines.size
    assert_match(/^,660,2025-09-01,09:00,ID,/, lines[1])
  end

  test "an export carries the person filter too" do
    create_entry(on_duty: at(9), off_duty: at(12))
    create_entry(on_duty: at(9), off_duty: at(12), who: @admin)

    get shift_operations_payroll_export_path(query(person_id: @ranger.id).merge(format: :csv))

    body = response.body
    assert_match(/E-2002/, body)
    assert_no_match(/E-1001/, body)
  end

  test "the file is named for the pay window" do
    create_entry(on_duty: at(9), off_duty: at(12))

    get shift_operations_payroll_export_path(query.merge(format: :csv))

    assert_match(/payroll-2025-09-01-to-2025-09-01-adjusted\.csv/,
                 response.headers["Content-Disposition"])
  end

  # A download asked for without a window has nothing to build from, and a
  # blank file would look like a pay period with no one in it.
  test "a download with no parameters lands back on the page" do
    get shift_operations_payroll_export_path(format: :csv)

    assert_redirected_to shift_operations_payroll_export_path
  end

  # A bookmarked download whose period has since gone stale has to arrive at the
  # reason, not at an empty form it cannot tell apart from a fresh visit.
  test "a download refused by validation carries what was asked for back" do
    get shift_operations_payroll_export_path(
      query(end_time: (at(0) + 120.days).strftime("%Y-%m-%dT%H:%M")).merge(format: :csv)
    )

    follow_redirect!

    assert_response :success
    assert_match(/cannot be longer than/, response.body)
  end
end
