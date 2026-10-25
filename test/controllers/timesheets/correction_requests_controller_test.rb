# frozen_string_literal: true

require "test_helper"

class Timesheets::CorrectionRequestsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include EscapedMarkupTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers
  include DomIdTestHelper

  # Above the 2018 floor and clear of the timesheet fixtures, which occupy
  # 2023-2025. travel_to makes it the current year, so setup_year admits it.
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

    sign_in_as(@admin)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  # --- factories ---------------------------------------------------------

  # record_notes types the note from Current.person_id: the requester's own
  # words when it matches, somebody writing on their behalf when it does not.
  # Left unset, every note lands as an authorless hq-worker note, which is not
  # what either page is read against.
  def as_person(person)
    was = Current.person
    Current.person = person
    yield
  ensure
    Current.person = was
  end

  def create_correction!(person: @event_manager, position: @position,
                         on_duty: @now, hours: 6,
                         review_status: Timesheet::STATUS_PENDING,
                         off_duty: :default, notes: "Signed in on the wrong position",
                         author: nil)
    off_duty = on_duty + hours.hours if off_duty == :default

    as_person(author || person) do
      Timesheet.create!(person:, position:, on_duty:, off_duty:,
                        review_status:, additional_notes: notes)
    end
  end

  def create_missing!(person: @outsider, position: @position, on_duty: @now,
                      hours: 6, review_status: TimesheetMissing::STATUS_PENDING,
                      notes: "Never got signed in for this shift", author: nil)
    as_person(author || person) do
      TimesheetMissing.create!(person_id: person.id, create_person_id: person.id,
                               position_id: position.id, on_duty:,
                               off_duty: on_duty + hours.hours, partner: "none",
                               review_status:, additional_notes: notes)
    end
  end

  # --- authorization -----------------------------------------------------

  # Upstream's TimesheetPolicy::before grants Admin and Timesheet Management
  # every method on the policy; correctionRequests() adds no one, so this page
  # is closed to the Event Management reader who may open most of the other
  # /timesheets reports.
  test "admin and timesheet management may view the report" do
    timesheet_manager = person(:auditor_ranger)
    grant_role(timesheet_manager, Role::TIMESHEET_MANAGEMENT)

    [@admin, timesheet_manager].each do |viewer|
      sign_in_as(viewer)
      get timesheets_correction_requests_path(year: YEAR)
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "event management is turned away from this report" do
    sign_in_as(@event_manager)

    get timesheets_correction_requests_path(year: YEAR)

    assert_redirected_to me_root_path
  end

  test "someone without the role is turned away" do
    sign_in_as(@outsider)

    get timesheets_correction_requests_path(year: YEAR)

    assert_redirected_to me_root_path
  end

  # --- what the report holds ---------------------------------------------

  test "a year with nothing outstanding says so" do
    get timesheets_correction_requests_path(year: YEAR)

    assert_response :success
    assert_select "*", text: /Nothing is waiting/
  end

  test "both a pending timesheet and a pending missing request are listed" do
    create_correction!
    create_missing!

    get timesheets_correction_requests_path(year: YEAR)

    assert_response :success
    assert_select "th", text: @event_manager.callsign
    assert_select "th", text: @outsider.callsign
    # Scoped to the table: "Correction" on its own also matches the page title,
    # which would pass with an empty table.
    assert_select "tbody td", text: /Correction/
    assert_select "tbody td", text: /Missing Entry/
  end

  # Only pending rows are outstanding: anything else has already been decided.
  test "decided requests are left out" do
    create_correction!(review_status: Timesheet::STATUS_VERIFIED)
    create_missing!(review_status: TimesheetMissing::STATUS_APPROVED)

    get timesheets_correction_requests_path(year: YEAR)

    assert_response :success
    assert_select "*", text: /Nothing is waiting/
  end

  # Upstream's whereNotNull: a pending entry still running has no span to
  # correct yet, and its duration would be measured against right now.
  test "a pending entry still on duty is left out" do
    create_correction!(off_duty: nil)

    get timesheets_correction_requests_path(year: YEAR)

    assert_response :success
    assert_select "*", text: /Nothing is waiting/
  end

  test "another year's requests are left out" do
    create_correction!(on_duty: Time.zone.local(YEAR - 1, 8, 26, 12, 0, 0))

    get timesheets_correction_requests_path(year: YEAR)

    assert_response :success
    assert_select "*", text: /Nothing is waiting/
  end

  test "requests are listed in callsign order" do
    # auditor_ranger and echelon_ranger, whichever way the fixtures sort.
    other = person(:auditor_ranger)
    create_correction!(person: @event_manager)
    create_missing!(person: other)

    get timesheets_correction_requests_path(year: YEAR)

    assert_response :success
    callsigns = css_select("tbody th").map { |th| th.text.strip }
    assert_equal callsigns.sort_by(&:downcase), callsigns
  end

  # --- the reason, which upstream returned and never drew -----------------

  # Both sides, because they reach their notes through separate associations on
  # separate models: a rename or a dropped eager load on the missing side would
  # quietly render every missing-entry row as "None given".
  test "the reason a request was made is on the page" do
    create_correction!(notes: "Signed in on the wrong position")
    create_missing!(notes: "HQ never signed me in for this shift")

    get timesheets_correction_requests_path(year: YEAR)

    assert_response :success
    assert_select "*", text: /Signed in on the wrong position/
    assert_select "*", text: /HQ never signed me in for this shift/
  end

  test "a request carrying a reason offers a control that opens it" do
    entry = create_correction!

    get timesheets_correction_requests_path(year: YEAR)

    assert_response :success
    detail_id = "correction-request-detail-timesheet-#{entry.id}"
    assert_select "##{detail_id}"
    assert_select "button[aria-controls=?][data-toggle-dom-id-value=?]", detail_id, detail_id
  end

  # "The ranger says their hours are wrong" and "the HQ window says so" are
  # different claims to weigh, so a note written on someone's behalf names the
  # desk it came from rather than passing as the ranger's own words.
  test "a note written on someone's behalf names the desk it came from" do
    create_correction!(person: @event_manager, author: @admin)

    get timesheets_correction_requests_path(year: YEAR)

    assert_response :success
    assert_select "*", text: /#{@admin.callsign} \(HQ Window\)/
  end

  # An admin note is the reviewer talking to other reviewers, not the ranger
  # explaining themselves, so it is not the reason the request was made.
  test "admin notes are not shown as the reason" do
    entry = create_correction!(notes: "The ranger's own words")
    TimesheetNote.record(entry.id, @admin.id, "Reviewer chatter", TimesheetNote::TYPE_ADMIN)

    request = create_missing!(notes: "The missing shift in their words")
    TimesheetMissingNote.record(request.id, @admin.id, "Missing-side chatter",
                                TimesheetMissingNote::TYPE_ADMIN)

    get timesheets_correction_requests_path(year: YEAR)

    assert_response :success
    assert_select "*", text: /The ranger's own words/
    assert_select "*", text: /The missing shift in their words/
    assert_no_match(/Reviewer chatter/, response.body)
    assert_no_match(/Missing-side chatter/, response.body)
  end

  # --- the letter filter --------------------------------------------------

  test "the letter filter narrows the table and its rollups alike" do
    create_correction!(person: @event_manager)
    create_missing!(person: @outsider)

    letter = @event_manager.callsign[0].upcase
    # Asserted rather than skipped: a fixture rename that collided these two
    # would otherwise retire the only test covering the filter, silently.
    assert_not_equal letter, @outsider.callsign[0].upcase,
                     "the two fixtures must start with different letters for " \
                     "this test to mean anything"

    get timesheets_correction_requests_path(year: YEAR, letter:)

    assert_response :success
    assert_select "th", text: @event_manager.callsign
    assert_select "th", text: @outsider.callsign, count: 0
    # The count line and the stat boxes report the filtered set, not the year.
    assert_select "*", text: /Showing 1 of 2 requests/
  end

  test "a letter no one's callsign starts with is ignored" do
    create_correction!(person: @event_manager)

    get timesheets_correction_requests_path(year: YEAR, letter: "Z")

    assert_response :success
    assert_select "th", text: @event_manager.callsign
    assert_select "*", text: /Showing 1 of 1 request/
  end

  # `?letter[]=A` arrives as an Array, which is neither a String nor one
  # character long.
  test "an array letter param is ignored" do
    create_correction!(person: @event_manager)

    get timesheets_correction_requests_path(year: YEAR, letter: ["A"])

    assert_response :success
    assert_select "th", text: @event_manager.callsign
  end

  # --- page plumbing ------------------------------------------------------

  # Without it, applying a filter snaps the page back to the current year.
  test "the filter form carries the year" do
    create_correction!

    get timesheets_correction_requests_path(year: YEAR)

    assert_response :success
    assert_select "#correction-requests-filters input[name=year][value=?]", YEAR.to_s
  end

  # datetime_format returns a <span>; interpolated instead of rendered, the
  # markup is escaped into the page.
  test "times are rendered as markup rather than escaped" do
    create_correction!

    get timesheets_correction_requests_path(year: YEAR)

    assert_response :success
    assert_no_escaped_markup
  end

  test "the page has no duplicate dom ids" do
    create_correction!
    create_missing!

    get timesheets_correction_requests_path(year: YEAR)

    assert_response :success
    assert_unique_dom_ids
  end

  # The two tables draw ids from their own sequences, so they collide freely --
  # and auto-increment ids in a test almost never do, which is why the collision
  # is forced here rather than hoped for. Drop the model from dom_key and this
  # is the test that says so.
  test "a correction and a missing request sharing an id get different dom keys" do
    keys = [false, true].map do |missing|
      CorrectionRequestsReport::Entry.new(
        id: 42, missing:, person: nil, person_id: @admin.id, callsign: "Testy",
        position_title: "Dirt", on_duty: @now, off_duty: @now + 1.hour,
        duration: 3600, credits: 0.0, notes: []
      ).dom_key
    end

    assert_equal keys.uniq, keys
  end

  # --- CSV export ---------------------------------------------------------

  test "the export carries the rows, the reason, and the active filter" do
    create_correction!(person: @event_manager, notes: "Signed in on the wrong position")
    create_missing!(person: @outsider)

    letter = @event_manager.callsign[0].upcase
    assert_not_equal letter, @outsider.callsign[0].upcase,
                     "the two fixtures must start with different letters for " \
                     "this test to mean anything"

    get timesheets_correction_requests_path(year: YEAR, letter:, format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/#{YEAR}-correction-requests\.csv/, response.headers["Content-Disposition"])

    # Asserted against the raw text: the app builds CSV by hand and does not
    # load the stdlib library anywhere, so neither does its test.
    body = response.body
    assert_equal "Callsign,Type,Position,On Duty,Off Duty,Hours,Credits,Reason",
                 body.lines.first.chomp
    # The filter rides along, so the file and the page hold the same rows. The
    # single note on this row spans one line, so the file is header plus one.
    assert_equal 2, body.lines.size
    assert_includes body, @event_manager.callsign
    assert_not_includes body, @outsider.callsign
    assert_includes body, "Correction"
    # The reason travels with the row -- it is the whole point of the page.
    assert_includes body, "Signed in on the wrong position"
    # Wall clock as stored, not converted into the host's zone.
    assert_includes body, @now.strftime("%FT%T")
  end

  test "the export link carries the active filter" do
    create_correction!(person: @event_manager)

    letter = @event_manager.callsign[0].upcase

    get timesheets_correction_requests_path(year: YEAR, letter:)

    assert_response :success
    assert_select "a[href*='.csv'][href*=?]", "letter=#{letter}"
  end
end
