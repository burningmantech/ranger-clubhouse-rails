# frozen_string_literal: true

require "test_helper"

class Timesheets::TimesheetUnconfirmedControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role / confirm_timesheet_for
  include ActiveSupport::Testing::TimeHelpers
  include DomIdTestHelper
  include ReportCardTestHelper # card_answer / assert_no_card_question

  YEAR = 2031
  # The two groups' headings. Each is spelled once: its section prints it and
  # the About This Report card quotes it, and a test that expects a question
  # gone would keep passing against wording that had merely changed.
  TO_VERIFY_HEADING = "Still Have Entries to Verify"
  TO_CONFIRM_HEADING = "Have Not Confirmed Yet"

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
    @outsider = person(:auditor_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)

    @position = positions(:ood_position)
    @unverified = person(:inactive_ranger)
    @unconfirmed = person(:retired_ranger)

    sign_in_as(@admin)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  def log_hours(who, review_status: Timesheet::STATUS_UNVERIFIED, on_duty: @now)
    Timesheet.create!(person: who, position: @position, on_duty:, review_status:,
                      additional_notes: "test shift")
  end

  # The card's question about one group, quoting that group's heading.
  def card_question(heading) = "Who is under “#{heading}”?"

  # The whole report in one setup: one ranger owing verifications, one owing
  # only the final click.
  def both_groups
    log_hours(@unverified)
    log_hours(@unconfirmed, review_status: Timesheet::STATUS_VERIFIED)
  end

  # Upstream's TimesheetPolicy@unconfirmedPeople admits Timesheet Management
  # alone, so this page is closed to the Event Management reader who may open
  # the On Duty and Forced Shift Start reports.
  test "admin and timesheet management may view the report" do
    timesheet_manager = @outsider
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)

    [@admin, timesheet_manager].each do |viewer|
      sign_in_as(viewer)
      get timesheets_timesheet_unconfirmed_path(year: YEAR)
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "event management is turned away from this report" do
    sign_in_as(@event_manager)

    get timesheets_timesheet_unconfirmed_path(year: YEAR)

    assert_redirected_to me_root_path
  end

  test "someone without the role is turned away" do
    sign_in_as(@outsider)

    get timesheets_timesheet_unconfirmed_path(year: YEAR)

    assert_redirected_to me_root_path
  end

  test "a year everyone confirmed says so" do
    log_hours(@unconfirmed)
    confirm_timesheet_for(@unconfirmed, YEAR)

    get timesheets_timesheet_unconfirmed_path(year: YEAR)

    assert_response :success
    assert_select "*", text: /Everyone who rangered in #{YEAR} has confirmed/
  end

  test "the two groups are shown apart, each with its own heading" do
    both_groups

    get timesheets_timesheet_unconfirmed_path(year: YEAR)

    assert_response :success
    assert_select "*", text: /1 Ranger — #{TO_VERIFY_HEADING}/
    assert_select "*", text: /1 Ranger — #{TO_CONFIRM_HEADING}/
    assert_select "th", text: @unverified.callsign
    assert_select "th", text: @unconfirmed.callsign
  end

  # Who is under a heading is explained in the About This Report card, and only
  # for a group the page has. One group a year, so each question is seen both
  # there and gone.
  test "the card explains only the group the page has" do
    log_hours(@unverified)
    log_hours(@unconfirmed, review_status: Timesheet::STATUS_VERIFIED, on_duty: @now - 1.year)

    get timesheets_timesheet_unconfirmed_path(year: YEAR)

    assert_not_empty card_answer(card_question(TO_VERIFY_HEADING))
    assert_no_card_question card_question(TO_CONFIRM_HEADING)

    get timesheets_timesheet_unconfirmed_path(year: YEAR - 1)

    assert_not_empty card_answer(card_question(TO_CONFIRM_HEADING))
    assert_no_card_question card_question(TO_VERIFY_HEADING)
  end

  test "the count column reports every open entry, not just the first" do
    both_groups
    log_hours(@unverified)

    get timesheets_timesheet_unconfirmed_path(year: YEAR)

    assert_select "td", text: "2"
    # The settled group has nothing to count, so it carries no count column.
    assert_select "th", text: "Entries to Verify", count: 1
  end

  test "contact details are reachable, not just printed" do
    @unverified.update_columns(home_phone: "+17075550123")
    both_groups

    get timesheets_timesheet_unconfirmed_path(year: YEAR)

    assert_select "a[href=?]", "mailto:#{@unverified.email}"
    # The stored E.164 is the tel: URI, + and all.
    assert_select "a[href=?]", "tel:+17075550123"
    assert_select "a", text: "(707) 555-0123"
  end

  # email is nullable; home_phone is NOT NULL and defaults to "". Both read as
  # missing, and an unfilled phone is ordinary.
  test "a ranger with no email or phone reads as missing, not blank" do
    @unverified.update_columns(email: nil, home_phone: "")
    both_groups

    get timesheets_timesheet_unconfirmed_path(year: YEAR)

    assert_response :success
    assert_select "td[data-label=Email]", text: ApplicationController.helpers.value_or_dash(nil)
    assert_select "td", text: /No phone/
    # Nothing to copy for that group, so only the other group keeps its button.
    assert_select "[data-controller='copy-to-clipboard']", count: 1
  end

  test "the year selector scopes the report" do
    log_hours(@unverified, on_duty: Time.zone.local(YEAR - 1, 8, 26, 12, 0, 0))

    get timesheets_timesheet_unconfirmed_path(year: YEAR)
    assert_select "th", text: @unverified.callsign, count: 0

    get timesheets_timesheet_unconfirmed_path(year: YEAR - 1)
    assert_select "th", text: @unverified.callsign
  end

  test "the page emits no duplicate DOM ids" do
    both_groups

    get timesheets_timesheet_unconfirmed_path(year: YEAR)

    assert_unique_dom_ids
  end

  test "the export carries the group so the split survives the download" do
    both_groups

    get timesheets_timesheet_unconfirmed_path(year: YEAR, format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/filename="#{YEAR}-timesheet-unconfirmed.csv"/,
                 response.headers["Content-Disposition"])

    rows = response.body.split("\n")
    assert_equal "Callsign,Name,Email,Home Phone,Unverified Entries,Group", rows.first
    assert_match(/\A#{@unverified.callsign},.*,1,Entries to verify\z/, rows[1])
    assert_match(/\A#{@unconfirmed.callsign},.*,0,Confirmation not given\z/, rows[2])
  end
end
