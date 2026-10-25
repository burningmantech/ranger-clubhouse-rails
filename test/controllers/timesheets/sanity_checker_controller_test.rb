# frozen_string_literal: true

require "test_helper"

class Timesheets::SanityCheckerControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ReportCardTestHelper     # assert_report_card / card_answer / assert_no_card_question

  # A year the timesheet fixtures leave alone -- they carry 2023, 2024, and
  # 2025 entries, which would ride along in every count.
  YEAR = 2022

  setup do
    Rails.cache.clear
    Current.reset

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")

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

  def entry(on_duty:, off_duty:, who: @admin, **attrs)
    Timesheet.create!(person: who, position: @position, on_duty:, off_duty:,
                      additional_notes: "test shift", **attrs)
  end

  # --- the gate ----------------------------------------------------------

  test "an admin may read the board" do
    get timesheets_sanity_checker_path(year: YEAR)
    assert_response :success
  end

  test "timesheet management may read the board" do
    sign_in_as(@timesheet_manager)
    get timesheets_sanity_checker_path(year: YEAR)
    assert_response :success
  end

  # Deliberately narrower than the /timesheets pages next door: upstream's
  # policy admits Admin and Timesheet Management alone.
  test "event management may not read the board" do
    sign_in_as(@event_manager)
    get timesheets_sanity_checker_path(year: YEAR)
    assert_redirected_to me_root_path
  end

  test "a person with no role may not read the board" do
    sign_in_as(@outsider)
    get timesheets_sanity_checker_path(year: YEAR)
    assert_redirected_to me_root_path
  end

  test "a check page is gated the same way as the board" do
    sign_in_as(@event_manager)
    get timesheets_sanity_checker_check_path("too-short", year: YEAR)
    assert_redirected_to me_root_path
  end

  # --- the board ---------------------------------------------------------

  test "a clean year shows every check under Clear" do
    get timesheets_sanity_checker_path(year: YEAR)

    assert_response :success
    assert_select "h2", text: "Clear"
    # Every check but the deferred one, which never reports a count and so is
    # never clear.
    Timesheets::SanityCheckerHelper::CHECK_META.each do |key, meta|
      next if key == TimesheetSanityCheckReport::DEFERRED_KEY

      assert_select "a[href=?]", timesheets_sanity_checker_check_path(key.to_s.dasherize,
                                                                     year: YEAR)
      assert_match meta[:label], response.body
    end
  end

  test "the no credits check is always offered without a count" do
    get timesheets_sanity_checker_path(year: YEAR)

    assert_response :success
    assert_select "a[href=?]", timesheets_sanity_checker_check_path("no-credits", year: YEAR)
    assert_match "Open to check", response.body
    # Its band heading is shown even in an otherwise clean year, because the
    # check has not been run.
    assert_select "h2", text: "Fix the Configuration"
  end

  test "a finding moves its check out of Clear and into its band" do
    entry(on_duty: august(20, 9), off_duty: august(20, 9, 5))

    get timesheets_sanity_checker_path(year: YEAR)

    assert_response :success
    assert_select "h2", text: "Review the Entry"
    assert_match "1 entry", response.body
  end

  # A band's title is an action, and the card says what is under each one on
  # the board. A band with nothing in it is not on the board, so it is not in
  # the card either; the credits band is always there.
  test "the card says what is under each band on the board" do
    bands = Timesheets::SanityCheckerHelper::BAND_META
    under = ->(band) { "What is under “#{bands[band][:title]}”?" }
    entry(on_duty: august(20, 9), off_duty: august(20, 9, 5))

    get timesheets_sanity_checker_path(year: YEAR)

    assert_report_card
    assert_equal bands[:review][:what], card_answer(under.call(:review))
    assert_equal bands[:configuration][:what], card_answer(under.call(:configuration))
    assert_no_card_question under.call(:contact)
  end

  test "counts are labelled with the check's own grain" do
    # duplicate_alphas counts people; too_short counts entries. The board must
    # never present the two as comparable numbers.
    alpha = Position.create!(id: Position::ALPHA, title: "Alpha",
                             type: Position::TYPE_FRONTLINE, active: true)
    2.times do |n|
      Timesheet.create!(person: @admin, position: alpha, on_duty: august(20 + n, 9),
                        off_duty: august(20 + n, 15), additional_notes: "test shift")
    end

    get timesheets_sanity_checker_path(year: YEAR)

    assert_response :success
    assert_match "1 person", response.body
  end

  # --- a check page ------------------------------------------------------

  test "a check page lists its findings and not another check's" do
    # NOT @admin: the layout greets the signed-in person by callsign on every
    # page, so asserting @admin's callsign appears would pass over an empty
    # table. The row is asserted through the table body for the same reason.
    entry(on_duty: august(20, 9), off_duty: august(20, 9, 5), who: @outsider)
    entry(on_duty: august(22, 0), off_duty: august(23, 16), who: @timesheet_manager)

    get timesheets_sanity_checker_check_path("too-short", year: YEAR)

    assert_response :success
    assert_select "tbody tr", 1
    assert_select "tbody th", text: @outsider.callsign
    # The long entry is a finding of a different check, on a different page.
    assert_select "tbody", text: /#{@timesheet_manager.callsign}/, count: 0
    # too_short has nothing more to say than its blurb, so it draws no card.
    assert_report_card count: 0
  end

  # The blurb is the check page's hero description, which says one thing. The
  # rest lives in question:/answer: and folds into the page's About card.
  test "every check's blurb is one sentence, and a question never comes without its answer" do
    Timesheets::SanityCheckerHelper::CHECK_META.each do |key, meta|
      assert_equal 1, meta[:blurb].scan(/[.!?](?=\s|\z)/).size, "#{key}: #{meta[:blurb]}"
      assert_equal meta.key?(:question), meta.key?(:answer),
                   "#{key} has one of question:/answer: without the other"
    end
  end

  test "a check with no findings says so rather than showing an empty table" do
    get timesheets_sanity_checker_check_path("too-short", year: YEAR)

    assert_response :success
    assert_match Timesheets::SanityCheckerHelper::CHECK_META[:too_short][:empty],
                 response.body
    assert_select "table", false
  end

  test "the too long page shows the maximum each entry was measured against" do
    gerlach = Position.create!(id: Position::GERLACH_PATROL, title: "Gerlach Patrol",
                               type: Position::TYPE_FRONTLINE, active: true)
    Timesheet.create!(person: @admin, position: gerlach, on_duty: august(20, 0),
                      off_duty: august(21, 0), additional_notes: "test shift")
    # An unlisted position past the default, so both thresholds appear.
    entry(on_duty: august(22, 0), off_duty: august(23, 16), who: @timesheet_manager)

    get timesheets_sanity_checker_check_path("too-long", year: YEAR)

    assert_response :success
    assert_select "td", text: Position::PROBLEM_HOURS[Position::GERLACH_PATROL].to_s
    assert_select "td", text: TimesheetSanityCheckReport::DEFAULT_MAX_HOURS.to_s
  end

  # The person-grain partials take a different shape from _entries, and each is
  # reachable only from its own check. Without these two the pages render in no
  # test at all -- which is how a broken export shipped green.
  test "the overlapping page renders a row per Ranger" do
    entry(on_duty: august(20, 9), off_duty: august(20, 15), who: @outsider)
    entry(on_duty: august(20, 12), off_duty: august(20, 18), who: @outsider)

    get timesheets_sanity_checker_check_path("overlapping", year: YEAR)

    assert_response :success
    assert_select "tbody tr", 1
    assert_select "tbody th", text: @outsider.callsign
  end

  test "the duplicate alphas page renders a row per Ranger" do
    alpha = Position.create!(id: Position::ALPHA, title: "Alpha",
                             type: Position::TYPE_FRONTLINE, active: true)
    2.times do |n|
      Timesheet.create!(person: @outsider, position: alpha, on_duty: august(20 + n, 9),
                        off_duty: august(20 + n, 15), additional_notes: "test shift")
    end

    get timesheets_sanity_checker_check_path("duplicate-alphas", year: YEAR)

    assert_response :success
    assert_select "tbody tr", 1
    assert_select "tbody th", text: @outsider.callsign
  end

  test "the overlapping export carries a row per entry" do
    entry(on_duty: august(20, 9), off_duty: august(20, 15), who: @outsider)
    entry(on_duty: august(20, 12), off_duty: august(20, 18), who: @outsider)

    get timesheets_sanity_checker_check_path("overlapping", year: YEAR, format: :csv)

    assert_response :success
    # Header plus both entries of the one overlapping Ranger. The loader used
    # to drop them, leaving the header alone.
    assert_equal 3, response.body.split("\n").size
  end

  test "the still on duty page renders open entries" do
    Timesheet.create!(person: @outsider, position: @position, on_duty: august(20),
                      additional_notes: "test shift")

    get timesheets_sanity_checker_check_path("on-duty", year: YEAR)

    assert_response :success
    assert_select "tbody tr", 1
    # What to do about the rows is out of the hero and in the page's card.
    meta = Timesheets::SanityCheckerHelper::CHECK_META[:on_duty]
    assert_select "section.me-hero-panel", text: /#{Regexp.escape(meta[:blurb])}/
    assert_select "section.me-hero-panel", text: /#{Regexp.escape(meta[:answer])}/, count: 0
    assert_report_card
    assert_equal meta[:answer], card_answer(meta[:question])
  end

  test "the off duty before on duty page shows both dates" do
    row = entry(on_duty: august(25, 18), off_duty: august(25, 18), who: @outsider)
    row.update_columns(off_duty: august(20, 9))

    get timesheets_sanity_checker_check_path("end-before-start", year: YEAR)

    assert_response :success
    assert_select "tbody tr", 1
    # Both dates, not just the on-duty one: a five-day-backwards sign-out reads
    # as a same-week typo when the second date is dropped.
    assert_select "tbody td", text: /Aug 25.*Aug 20/m
    # And the span as a magnitude, not the floored negative clock.
    assert_select "tbody td", text: /-5 days 9 hours/
  end

  test "the no credits page renders and is capped" do
    entry(on_duty: august(20, 9), off_duty: august(20, 15), who: @outsider)

    get timesheets_sanity_checker_check_path("no-credits", year: YEAR)

    assert_response :success
    assert_select "tbody tr", 1
    assert_select "tbody th", text: @outsider.callsign
  end

  test "an unknown check goes back to the board with a reason" do
    get timesheets_sanity_checker_check_path("not-a-check", year: YEAR)

    assert_redirected_to timesheets_sanity_checker_path(year: YEAR)
    assert_equal Timesheets::SanityCheckerController::UNKNOWN_CHECK, flash[:error]
  end

  # --- the export --------------------------------------------------------

  test "a check exports its findings as CSV" do
    entry(on_duty: august(20, 9), off_duty: august(20, 9, 5))

    get timesheets_sanity_checker_check_path("too-short", year: YEAR, format: :csv)

    assert_response :success
    lines = response.body.split("\n")
    # The Email column is present because an Admin may see emails; a reader who
    # may not gets the same export without it.
    assert_equal "Callsign,Position,On Duty,Off Duty,Hours,Shift Begins," \
                 "Shift Duration,Shift Description,Email", lines.first
    assert_equal 2, lines.size
    assert_match @admin.callsign, lines.last
    # getlocal before iso8601 -- the stored wall clock, not a zone-shifted one.
    assert_match august(20, 9).getlocal.iso8601, lines.last
  end

  test "a person-grain check exports one row per entry, not per person" do
    alpha = Position.create!(id: Position::ALPHA, title: "Alpha",
                             type: Position::TYPE_FRONTLINE, active: true)
    2.times do |n|
      Timesheet.create!(person: @admin, position: alpha, on_duty: august(20 + n, 9),
                        off_duty: august(20 + n, 15), additional_notes: "test shift")
    end

    get timesheets_sanity_checker_check_path("duplicate-alphas", year: YEAR, format: :csv)

    assert_response :success
    # One header plus both entries of the single flagged person.
    assert_equal 3, response.body.split("\n").size
  end
end
