# frozen_string_literal: true

require "test_helper"

# The Early Arrivals report: its gate, who lands on it and why, where the window
# closes, what each row says, the ways of narrowing the list, and the export.
class Scheduling::EarlyArrivalsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper   # create_slot
  include PersonTestFactory        # create_person
  include ReportCardTestHelper     # card_answer

  # Passes, radio allowances, and the on-playa flag are only recorded as they
  # stand today, so the report answers in full for the event being prepared and
  # from shifts alone for anything earlier. The live tests therefore run on the
  # current year; PAST_YEAR covers the other half.
  YEAR = Current.year
  PAST_YEAR = YEAR - 4
  EVENT_START = Date.new(YEAR, 8, 30)
  # The same rule the report applies, so the fixture cannot drift out of the
  # window as the calendar moves. The shape of both dates is asserted below.
  CUTOFF = EVENT_START.prev_occurring(:thursday)
  WINDOW_OPENS = CUTOFF - 5

  DENY_MESSAGE = "Admin or Edit Access Documents role required " \
                 "to view the early arrivals report."

  PURPOSE_QUESTION = "What is it for?"
  CHASING_QUESTION = "What needs chasing?"

  setup do
    Rails.cache.clear
    Current.reset

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_ACCESS_DOCS, "Edit Access Documents")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")
    ensure_role(Role::VC, "Volunteer Coordinator")

    @admin = person(:active_ranger)
    @doc_editor = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@doc_editor, Role::EDIT_ACCESS_DOCS)
    grant_role(@outsider, Role::VC)

    @setup_position = Position.create!(title: "Pre-Event Setup", active: true)
    @training_position = Position.create!(title: "Setup Training",
                                          type: Position::TYPE_TRAINING, active: true)

    create_event_dates
    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # The report reads the event start; the other dates are here only because the
  # record insists on them.
  def create_event_dates(start = EVENT_START)
    EventDate.destroy_all
    EventDate.create!(event_start: start, event_end: start + 8.days,
                      pre_event_start: start - 3.weeks,
                      pre_event_slot_start: start - 3.weeks,
                      pre_event_slot_end: start,
                      post_event_end: start + 3.weeks)
  end

  # A moment inside the window, counted back from the cutoff Thursday.
  def in_window(days_before_cutoff = 3, hour = 8)
    date = CUTOFF - days_before_cutoff
    Time.zone.local(date.year, date.month, date.day, hour, 0, 0)
  end

  # A moment on a given date, for the boundary tests.
  def at(date, hour = 8) = Time.zone.local(date.year, date.month, date.day, hour, 0, 0)

  # Somebody holding an arrival pass. Without a date it is good at any time.
  def pass_holder(callsign, access_date: nil, any_time: false,
                  status: AccessDocument::CLAIMED)
    person = create_person(callsign)
    AccessDocument.create!(person:, type: AccessDocument::SAP, status:,
                           source_year: YEAR,
                           delivery_method: AccessDocument::DELIVERY_NONE,
                           access_date:, access_any_time: any_time)
    person
  end

  # Somebody signed up for a shift, whether or not they hold a pass.
  def shift_holder(callsign, begins:, position: @setup_position, person: nil, year: nil)
    person ||= create_person(callsign)
    slot = create_slot(position, begins:, ends: begins + 8.hours,
                       description: "Depot")
    # Slot stamps begins_year from begins on save, so this only has to be spelled
    # when a test wants the two to disagree.
    slot.update_column(:begins_year, year) if year && slot.begins_year != year
    PersonSlot.create!(person:, slot:)
    person
  end

  def callsigns_on_page = assigns_rows.map(&:callsign)

  # The rows the page actually drew, read back off the controller.
  def assigns_rows = @controller.view_assigns["rows"]

  def report = @controller.view_assigns["report"]

  # --- the gate -------------------------------------------------------------

  test "an admin may read the report" do
    get scheduling_early_arrivals_path(year: YEAR)
    assert_response :success
  end

  test "edit access documents may read the report" do
    sign_in_as(@doc_editor)
    get scheduling_early_arrivals_path(year: YEAR)
    assert_response :success
  end

  # Timesheet Management is deliberately NOT on this report: arrival passes are
  # the access document team's to issue, and the roles have to match the ones
  # that may touch the passes themselves.
  test "timesheet management may not read the report" do
    grant_role(@outsider, Role::TIMESHEET_MANAGEMENT)
    sign_in_as(@outsider)

    get scheduling_early_arrivals_path(year: YEAR)
    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "a reader with no relevant role is turned away" do
    sign_in_as(@outsider)
    get scheduling_early_arrivals_path(year: YEAR)
    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  # --- the two states with nothing to show ----------------------------------

  test "the report says so when the event dates are missing" do
    EventDate.destroy_all

    get scheduling_early_arrivals_path(year: YEAR)
    assert_response :success
    assert_match(/event dates are not set/i, response.body)
  end

  test "the report says so when no one arrives early" do
    get scheduling_early_arrivals_path(year: YEAR)
    assert_response :success
    assert_match(/No one is arriving before/i, response.body)
  end

  # --- who lands on the report ----------------------------------------------

  test "a dated pass, an any-time pass, and a shift each put somebody on the report" do
    pass_holder("Dated", access_date: in_window(1))
    pass_holder("Anytime", any_time: true)
    shift_holder("Shifty", begins: in_window(2))

    get scheduling_early_arrivals_path(year: YEAR)
    assert_response :success

    assert_equal %w[Anytime Dated Shifty], callsigns_on_page
  end

  test "a pass dated on or after the cutoff does not count" do
    pass_holder("TooLate", access_date: at(CUTOFF + 1))

    get scheduling_early_arrivals_path(year: YEAR)
    assert_equal [], callsigns_on_page
  end

  test "somebody with a shift but no pass is listed and flagged" do
    shift_holder("NoPass", begins: in_window(2))

    get scheduling_early_arrivals_path(year: YEAR)
    assert_equal ["NoPass"], callsigns_on_page
    assert_nil assigns_rows.first.sap_date
    assert_equal 1, report.no_sap_count
  end

  test "the card names the arrival pass for the year being prepared" do
    shift_holder("NoPass", begins: in_window(2))

    get scheduling_early_arrivals_path(year: YEAR)
    assert_match(/needs: when the person may arrive, /, card_answer(PURPOSE_QUESTION))
    assert_match(/\AA missing arrival pass, a missing pre-event shift, and an unsigned radio/,
                 card_answer(CHASING_QUESTION))
  end

  test "somebody with a pass but no shift is listed and flagged" do
    pass_holder("NoShift", any_time: true)

    get scheduling_early_arrivals_path(year: YEAR)
    assert_equal ["NoShift"], callsigns_on_page
    assert_nil assigns_rows.first.first_shift
    assert_equal 1, report.no_shift_count
  end

  test "a pass and a shift for the same person make one row" do
    person = pass_holder("Both", access_date: in_window(2))
    shift_holder("Both", begins: in_window(1), person:)

    get scheduling_early_arrivals_path(year: YEAR)
    assert_equal ["Both"], callsigns_on_page

    row = assigns_rows.first
    assert_equal in_window(2).to_date, row.sap_date
    assert_equal "Pre-Event Setup", row.first_shift.position_title
  end

  test "the earliest shift in the window is the one reported" do
    person = shift_holder("Early", begins: in_window(1))
    shift_holder("Early", begins: in_window(2), person:)

    get scheduling_early_arrivals_path(year: YEAR)
    assert_equal in_window(2), assigns_rows.first.first_shift.begins
  end

  # --- where the window closes ----------------------------------------------

  test "a shift during the cutoff Thursday is outside the window" do
    shift_holder("Thursday", begins: at(CUTOFF))

    get scheduling_early_arrivals_path(year: YEAR)
    assert_equal [], callsigns_on_page
  end

  test "a shift before the window opens does not count" do
    shift_holder("TooEarly", begins: at(WINDOW_OPENS - 1))

    get scheduling_early_arrivals_path(year: YEAR)
    assert_equal [], callsigns_on_page
  end

  test "a training session inside the window is not a pre-event shift" do
    shift_holder("Trainee", begins: in_window(2), position: @training_position)

    get scheduling_early_arrivals_path(year: YEAR)
    assert_equal [], callsigns_on_page
  end

  # The cutoff is the Thursday before the event opens, and the window runs the
  # five days back to the Saturday. Asserting the weekdays rather than two dates
  # the fixture derived from the same rule.
  test "the window runs from the Saturday to the Thursday" do
    get scheduling_early_arrivals_path(year: YEAR)

    assert_equal "Thursday", report.pre_event_end.strftime("%A")
    assert_equal "Saturday", report.pre_event_start.strftime("%A")
    assert_equal 5, (report.pre_event_end - report.pre_event_start).to_i
    assert report.pre_event_end < EVENT_START
    assert_equal WINDOW_OPENS, report.pre_event_start
    assert_equal CUTOFF, report.pre_event_end
  end

  # --- what a row carries ---------------------------------------------------

  test "a badge on file is reported and a missing one reads as none" do
    person = pass_holder("Badged", any_time: true)
    Bmid.create!(person:, year: YEAR, status: Bmid::SUBMITTED)
    pass_holder("Unbadged", any_time: true)

    get scheduling_early_arrivals_path(year: YEAR)

    badged, unbadged = assigns_rows
    assert_equal Bmid::SUBMITTED, badged.bmid_status
    assert_nil unbadged.bmid_status
    assert_match(/No BMID/, response.body)
  end

  test "the radio agreement reads unsigned when no record says otherwise" do
    person = pass_holder("Signed", any_time: true)
    event = PersonEvent.first_or_new_for_person_year(person.id, YEAR)
    event.asset_authorized = true
    event.save!(validate: false)
    pass_holder("Unsigned", any_time: true)

    get scheduling_early_arrivals_path(year: YEAR)

    signed, unsigned = assigns_rows
    assert signed.radio_agreement
    assert_not unsigned.radio_agreement
    assert_equal 1, report.unsigned_count
  end

  test "the largest radio entitlement is the count that counts" do
    person = pass_holder("Radios", any_time: true)
    Provision.create!(person:, type: Provision::EVENT_RADIO,
                      status: Provision::AVAILABLE, item_count: 1, source_year: YEAR,
                      expires_on: Date.new(YEAR, 12, 31))
    Provision.create!(person:, type: Provision::EVENT_RADIO,
                      status: Provision::AVAILABLE, item_count: 3, source_year: YEAR,
                      expires_on: Date.new(YEAR, 12, 31))

    get scheduling_early_arrivals_path(year: YEAR)
    assert_equal 3, assigns_rows.first.radios_allowed
  end

  test "an issued radio is reported with its barcode and whether it is an event radio" do
    person = pass_holder("Holder", any_time: true)
    asset = Asset.create!(barcode: "R-900", type: Asset::TYPE_RADIO,
                          year: YEAR, perm_assign: true)
    PersonAsset.create!(person:, asset:, checked_out: in_window(2))

    get scheduling_early_arrivals_path(year: YEAR)

    radios = assigns_rows.first.radios
    assert_equal 1, radios.size
    assert_equal "R-900", radios.first.barcode
    assert_equal "event", radios.first.label
  end

  test "a radio checked out in another year is not reported" do
    person = pass_holder("Stale", any_time: true)
    asset = Asset.create!(barcode: "R-901", type: Asset::TYPE_RADIO,
                          year: YEAR - 1, perm_assign: false)
    PersonAsset.create!(person:, asset:,
                        checked_out: in_window(2) - 1.year)

    get scheduling_early_arrivals_path(year: YEAR)
    assert_empty assigns_rows.first.radios
  end

  # --- narrowing the list ---------------------------------------------------

  test "each filter narrows the table" do
    pass_holder("Anytime", any_time: true)
    pass_holder("Dated", access_date: in_window(1))
    shift_holder("Shifty", begins: in_window(2))

    get scheduling_early_arrivals_path(year: YEAR, sap: "any")
    assert_equal ["Anytime"], callsigns_on_page

    get scheduling_early_arrivals_path(year: YEAR, sap: "dated")
    assert_equal ["Dated"], callsigns_on_page

    get scheduling_early_arrivals_path(year: YEAR, sap: "none")
    assert_equal ["Shifty"], callsigns_on_page

    get scheduling_early_arrivals_path(year: YEAR, shift: "yes")
    assert_equal ["Shifty"], callsigns_on_page

    get scheduling_early_arrivals_path(year: YEAR, shift: "no")
    assert_equal %w[Anytime Dated], callsigns_on_page

    get scheduling_early_arrivals_path(year: YEAR, arrival: in_window(1).to_date.to_s)
    assert_equal ["Dated"], callsigns_on_page

    get scheduling_early_arrivals_path(year: YEAR, shift_date: in_window(2).to_date.to_s)
    assert_equal ["Shifty"], callsigns_on_page
  end

  test "the on site and agreement filters narrow the table" do
    here = pass_holder("Here", any_time: true)
    here.update_column(:on_site, true)
    pass_holder("Away", any_time: true)

    get scheduling_early_arrivals_path(year: YEAR, site: "on")
    assert_equal ["Here"], callsigns_on_page

    get scheduling_early_arrivals_path(year: YEAR, site: "off")
    assert_equal ["Away"], callsigns_on_page

    get scheduling_early_arrivals_path(year: YEAR, agreement: "unsigned")
    assert_equal %w[Away Here], callsigns_on_page
  end

  # A filter narrows the table it sits above, never the boxes above it: the
  # boxes are the whole picture, and a reader chasing "3 unsigned" has to be
  # able to find all three after narrowing the list for another reason.
  test "a filter never changes the counts above the table" do
    pass_holder("Anytime", any_time: true)
    pass_holder("Dated", access_date: in_window(1))

    get scheduling_early_arrivals_path(year: YEAR, sap: "any")

    assert_equal ["Anytime"], callsigns_on_page
    assert_equal 2, report.total
    assert_equal 2, report.unsigned_count
  end

  test "a filter value the page does not offer shows everyone" do
    pass_holder("Anytime", any_time: true)
    pass_holder("Dated", access_date: in_window(1))

    get scheduling_early_arrivals_path(year: YEAR, sap: "bogus",
                                       arrival: "not-a-date")
    assert_equal %w[Anytime Dated], callsigns_on_page
  end

  test "a filtered page keeps its year" do
    pass_holder("Anytime", any_time: true)

    get scheduling_early_arrivals_path(year: YEAR, sap: "any")
    assert_response :success
    assert_select "input[name=year][value=?]", YEAR.to_s
  end

  # --- the export -----------------------------------------------------------

  test "the export carries every column and ignores the filters" do
    person = pass_holder("Exported", access_date: in_window(1))
    shift_holder("Exported", begins: in_window(2), person:)
    pass_holder("Filtered", any_time: true)

    get scheduling_early_arrivals_path(year: YEAR, sap: "any", format: :csv)
    assert_response :success

    lines = response.body.split("\n")
    assert_equal "Callsign,SAP,First Pre-Event Position,Shift Start," \
                 "Shift Description,BMID Status,On Site,Radio Agreement," \
                 "Radio Count,Radio Barcode,Radio Type",
                 lines.first

    # Both people, though the URL asked for only the any-time one.
    assert_equal 3, lines.size
    assert_match(/^Exported,#{in_window(1).to_date},Pre-Event Setup,/, lines[1])
    # No shift, so the position, start, and description cells are all empty.
    assert_match(/^Filtered,Any time,,,,/, lines[2])
  end

  # --- an earlier year, which keeps no record of passes ----------------------

  # The event dates for an earlier year, so its half of the report can be built.
  def past_event_dates
    start = Date.new(PAST_YEAR, 8, 30)
    EventDate.create!(event_start: start, event_end: start + 8.days,
                      pre_event_start: start - 3.weeks,
                      pre_event_slot_start: start - 3.weeks,
                      pre_event_slot_end: start,
                      post_event_end: start + 3.weeks)
    start.prev_occurring(:thursday)
  end

  # The bug this guards: passes carry no history, so reading them for an earlier
  # year listed everybody holding a live pass today as having arrived back then.
  test "an earlier year ignores passes entirely" do
    cutoff = past_event_dates
    pass_holder("LivePass", any_time: true)

    get scheduling_early_arrivals_path(year: PAST_YEAR)
    assert_response :success
    assert_equal [], callsigns_on_page
    assert_not report.live?
  end

  test "an earlier year still lists whoever held a pre-event shift" do
    cutoff = past_event_dates
    shift_holder("Setup", begins: Time.zone.local(cutoff.year, cutoff.month, cutoff.day - 2, 8),
                 year: PAST_YEAR)

    get scheduling_early_arrivals_path(year: PAST_YEAR)
    assert_equal ["Setup"], callsigns_on_page

    row = assigns_rows.first
    assert_nil row.on_site, "the on-playa flag is live, so an earlier year cannot answer it"
    assert_equal 0, row.radios_allowed
  end

  test "an earlier year says why it is reading shifts alone" do
    past_event_dates
    get scheduling_early_arrivals_path(year: PAST_YEAR)

    assert_match(/read from its shifts alone/i, response.body)
    assert_no_match(/Passes Good Any Time/, response.body)
  end

  # Its table reads "Not recorded" where a pass would be and "Allowance not
  # recorded" over the radios, so the card must promise neither.
  test "an earlier year's card does not promise a pass or a radio allowance" do
    cutoff = past_event_dates
    shift_holder("Setup", begins: at(cutoff - 2))

    get scheduling_early_arrivals_path(year: PAST_YEAR)
    purpose = card_answer(PURPOSE_QUESTION)
    assert_no_match(/may arrive|may draw/, purpose)
    assert_match(/, and the radios issued to them\.\z/, purpose)

    chasing = card_answer(CHASING_QUESTION)
    assert_no_match(/arrival pass/, chasing)
    assert_match(/\AA missing pre-event shift and an unsigned radio agreement are each called/,
                 chasing)
  end

  test "an earlier year does not offer the filters it cannot answer" do
    cutoff = past_event_dates
    shift_holder("Setup", begins: Time.zone.local(cutoff.year, cutoff.month, cutoff.day - 2, 8),
                 year: PAST_YEAR)

    # A value supplied anyway narrows nothing rather than emptying the table.
    get scheduling_early_arrivals_path(year: PAST_YEAR, sap: "none", site: "on")
    assert_equal ["Setup"], callsigns_on_page
    assert_select "select[name=sap]", false
    assert_select "select[name=site]", false
  end

  # --- boundaries the window turns on ---------------------------------------

  # Midnight on the cutoff Thursday is INSIDE the window -- five real shifts a
  # year start exactly there. Anything later that day is outside.
  test "a shift beginning at midnight on the cutoff Thursday counts" do
    shift_holder("Midnight", begins: at(CUTOFF, 0))

    get scheduling_early_arrivals_path(year: YEAR)
    assert_equal ["Midnight"], callsigns_on_page
  end

  test "a shift beginning at the moment the window opens counts" do
    shift_holder("Opening", begins: at(WINDOW_OPENS, 0))

    get scheduling_early_arrivals_path(year: YEAR)
    assert_equal ["Opening"], callsigns_on_page
  end

  # --- entitlements and the export ------------------------------------------

  # An entitlement with no count means one radio, which is what the HQ window
  # hands over. Read as stored it would be nothing at all.
  test "an entitlement with no count on it means one radio" do
    person = pass_holder("Blank", any_time: true)
    provision = Provision.create!(person:, type: Provision::EVENT_RADIO,
                                  status: Provision::AVAILABLE, source_year: YEAR,
                                  expires_on: Date.new(YEAR, 12, 31))
    # The model fills a blank count in on save, so the blank has to be put back
    # underneath it -- legacy and bulk-loaded rows carry one.
    provision.update_column(:item_count, nil)

    get scheduling_early_arrivals_path(year: YEAR)
    assert_equal 1, assigns_rows.first.radios_allowed
  end

  test "the export carries every radio a person holds, in barcode order" do
    person = pass_holder("Loaded", any_time: true)
    ["R-902", "R-900"].each_with_index do |barcode, index|
      asset = Asset.create!(barcode:, type: Asset::TYPE_RADIO, year: YEAR,
                            perm_assign: index.zero?)
      PersonAsset.create!(person:, asset:, checked_out: in_window(2))
    end

    get scheduling_early_arrivals_path(year: YEAR)
    assert_equal %w[R-900 R-902], assigns_rows.first.radios.map(&:barcode)

    get scheduling_early_arrivals_path(year: YEAR, format: :csv)
    # Both barcodes ride in one quoted cell, newline separated.
    assert_match(/"R-900\nR-902"/, response.body)
    assert_match(/"shift\nevent"/, response.body)
  end

  test "the export refuses a year whose event dates are missing" do
    EventDate.destroy_all

    get scheduling_early_arrivals_path(year: YEAR, format: :csv)
    assert_redirected_to scheduling_early_arrivals_path(year: YEAR)
    assert_match(/event dates are not set/i, flash[:alert])
  end

  # --- the page when a filter matches no one --------------------------------

  test "a filter matching no one says so rather than showing an empty table" do
    pass_holder("Anytime", any_time: true)

    get scheduling_early_arrivals_path(year: YEAR, sap: "none")
    assert_equal [], callsigns_on_page
    assert_match(/No one matches the current filters/i, response.body)
  end

  # The year selector posts its own GET carrying only the year, so the filters
  # have to ride along as hidden fields or changing year silently widens the
  # list back out.
  test "the year selector carries the active filters" do
    pass_holder("Anytime", any_time: true)

    get scheduling_early_arrivals_path(year: YEAR, sap: "any")
    assert_select "form select#year-selector-compact"
    assert_select "form input[type=hidden][name=sap][value=any]"
  end
end
