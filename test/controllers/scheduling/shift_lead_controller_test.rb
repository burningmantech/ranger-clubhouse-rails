# frozen_string_literal: true

require "test_helper"

# The Shift Lead Report page: its gate, its shift picker, and the two flavours
# of report it renders.
class Scheduling::ShiftLeadControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include DomIdTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2025
  DENY_MESSAGE = "Event Management role required to read the Shift Lead Report."

  setup do
    # Half an hour into the shift below.
    travel_to Time.zone.local(YEAR, 8, 27, 12, 30, 0)
    Rails.cache.clear
    Current.reset

    @dirt = Position.create!(id: Position::DIRT, title: "Dirt", short_title: "Dirt",
                             type: Position::TYPE_FRONTLINE, active: true)
    @green_dot = Position.create!(id: Position::DIRT_GREEN_DOT, title: "Dirt - Green Dot",
                                  short_title: "GD", type: Position::TYPE_FRONTLINE,
                                  active: true, on_sl_report: true)
    @gd_training = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                    type: Position::TYPE_TRAINING, active: true)
    @troubleshooter = Position.create!(id: Position::TROUBLESHOOTER, title: "Troubleshooter",
                                       short_title: "TShoot", type: Position::TYPE_FRONTLINE,
                                       active: true, on_sl_report: true)

    @slot = create_slot(@dirt, begins: Time.zone.local(YEAR, 8, 27, 12, 0, 0),
                        ends: Time.zone.local(YEAR, 8, 27, 18, 0, 0), min: 1, max: 4)
    @other_year_slot = create_slot(@dirt, begins: Time.zone.local(2024, 8, 27, 12, 0, 0),
                                   ends: Time.zone.local(2024, 8, 27, 18, 0, 0))

    @admin = person(:auditor_ranger)
    @event_manager = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::VC, "Volunteer Coordinator")
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
    grant_role(@outsider, Role::VC)

    Current.person = @admin
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- authorization ---

  test "an admin can read the report" do
    sign_in_as(@admin)
    get scheduling_shift_lead_path(year: YEAR)

    assert_response :success
  end

  test "event management can read the report" do
    sign_in_as(@event_manager)
    get scheduling_shift_lead_path(year: YEAR)

    assert_response :success
  end

  # The report carries gender, pronouns, vehicle standing and certifications for
  # a whole shift, so the gate stays exactly as narrow as upstream's.
  test "a role outside the gate is turned away" do
    sign_in_as(@outsider)
    get scheduling_shift_lead_path(year: YEAR)

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "the live report is behind the same gate" do
    sign_in_as(@outsider)
    get scheduling_shift_lead_path(mode: "on-duty", year: YEAR)

    assert_redirected_to me_root_path
  end

  # --- the first view ---

  test "nothing is reported until a shift is picked" do
    sign_up(create_person("Dusty"), @slot)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR)

    assert_response :success
    assert_select "select#slot_id"
    assert_select "table", false
    assert_no_match "Dusty", response.body
  end

  # The picker is touched once and then left alone, so once it has done its job
  # it gives its height back to the roster. The subtitle says what is picked, so
  # folding it hides no answer.
  test "the shift picker starts open and folds once a shift is picked" do
    sign_up(create_person("Dusty"), @slot)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR)
    assert_select "details[open] select#slot_id"

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)
    assert_select "details:not([open]) select#slot_id"
    # Folded, the summary still says which shift the page is reporting on.
    assert_select "summary", text: /Aug 27 @ 12:00 - 18:00/
  end

  test "the live report folds the picker and says so" do
    sign_in_as(@admin)

    get scheduling_shift_lead_path(mode: "on-duty", year: YEAR)

    assert_select "details:not([open]) select#slot_id"
    assert_select "summary", text: /Whoever is signed in right now/
  end

  test "a year with no dirt shifts says so" do
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: 2019)

    assert_response :success
    assert_select "select#slot_id", false
    assert_match "No dirt shifts were scheduled for 2019.", response.body
  end

  # --- the scheduled report ---

  test "picking a shift reports who signed up for it" do
    sign_up(create_person("Dusty"), @slot)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)

    assert_response :success
    assert_select "option[selected][value=?]", @slot.id.to_s
    assert_select "h1", text: /Shift Lead Report/
    # The callsign opens the Ranger's page -- everyone through this gate may
    # read one.
    assert_select "th[scope=row] a", text: "Dusty"
    # Every roster is rendered twice, a table and a stack of blocks, so this
    # page has more chance than most of repeating an id.
    assert_unique_dom_ids
  end

  # Ten columns cannot be shown on a phone, so below lg the roster is a block
  # per Ranger instead. Both renderings ship on every request and carry the same
  # fields -- nothing on the phone is behind a tap or off the side of the page.
  test "each roster ships a phone rendering beside the table" do
    dusty = create_person("Dusty")
    dusty.update!(on_site: false)
    sign_up(dusty, @slot)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)

    assert_select "#shift-lead-dirt .hidden.lg\\:block table"
    assert_select "#shift-lead-dirt .lg\\:hidden a", text: "Dusty"
    # Both vehicle answers are always shown, never only the yesses: a chip that
    # appears only when the answer is yes asks the reader to read meaning into a
    # missing chip.
    assert_select "#shift-lead-dirt .lg\\:hidden span.badge", text: /GTR/
    assert_select "#shift-lead-dirt .lg\\:hidden span.badge", text: /VEH/
  end

  test "a qualified Green Dot gets a chip and an untrained one does not" do
    verde = create_person("Verde")
    PersonPosition.create!(person: verde, position: @green_dot)
    training = create_slot(@gd_training, begins: Time.zone.local(YEAR, 7, 1, 9, 0, 0),
                           ends: Time.zone.local(YEAR, 7, 1, 17, 0, 0))
    TraineeStatus.create!(person_id: verde.id, slot_id: training.id, status: TraineeStatus::STATUS_PASSED)

    untrained = create_person("Hopeful")
    PersonPosition.create!(person: untrained, position: @green_dot)

    gd_slot = create_slot(@green_dot, begins: @slot.begins, ends: @slot.ends)
    sign_up(verde, gd_slot)
    sign_up(untrained, gd_slot)

    sign_in_as(@admin)
    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)

    assert_response :success
    # Exactly one GD chip on the roster -- Verde's. The legend carries a second
    # one as an example, so the count is scoped to the table.
    assert_select "th[scope=row] span.badge-success", text: "GD", count: 1
    # Both callsigns are on the roster, so the absence above is about the chip
    # and not about Hopeful having been filtered out of the report.
    assert_select "th[scope=row] a", text: "Hopeful"
    assert_select "th[scope=row] a", text: "Verde"
  end

  test "a Troubleshooter who is not running the shift gets a chip" do
    wrench = create_person("Wrench")
    PersonPosition.create!(person: wrench, position: @troubleshooter)
    sign_up(wrench, @slot)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)

    assert_select "th[scope=row] span.badge-secondary", text: "TS", count: 1
  end

  test "a Ranger who is not marked on site is flagged" do
    dusty = create_person("Dusty")
    dusty.update!(on_site: false)
    sign_up(dusty, @slot)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)

    assert_select "i.fa-ban"
    assert_match "Not marked as being on site.", response.body
  end

  test "a shift short of its minimum is called out with what it has" do
    @slot.update!(min: 3, max: 3, signed_up: 1)
    sign_up(create_person("Dusty"), @slot)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)

    assert_select "#shift-lead-below-min th[scope=row]", text: "Dirt"
    # Pinned to their columns: a bare "some td reads 1" would still pass with the
    # have and need cells swapped, and an under-staffed position would then read
    # as over-staffed.
    assert_select "#shift-lead-below-min thead th:nth-of-type(3)", text: "Signed up"
    assert_select "#shift-lead-below-min thead th:nth-of-type(4)", text: "Needed"
    assert_select "#shift-lead-below-min tbody tr td:nth-of-type(2)", text: "1"
    assert_select "#shift-lead-below-min tbody tr td:nth-of-type(3)", text: "3"
  end

  test "a shift no one has signed up for says none rather than a bare zero" do
    @slot.update!(min: 2, max: 2, signed_up: 0)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)

    assert_select "#shift-lead-below-min tbody tr td:nth-of-type(2) span.text-error", text: "none"
    assert_select "#shift-lead-below-min tbody tr td:nth-of-type(3)", text: "2"
  end

  # The count is the alarm and it never hides; the list behind it starts folded,
  # because open it measured ~500px and pushed the first Ranger off a phone.
  test "the shortfall list starts folded and the band carries the count" do
    @slot.update!(min: 2, max: 2, signed_up: 0)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)

    assert_select "#shift-lead-below-min details:not([open])"
    assert_select "[aria-label='Shift summary']", text: /Below Minimum/
  end

  test "a fully staffed shift says so" do
    @slot.update!(min: 1, signed_up: 1)
    sign_up(create_person("Dusty"), @slot)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)

    assert_match "Every position has enough Rangers.", response.body
  end

  # --- the live report ---

  # Signing up for the shift running now is not the same as being on it.
  test "the live report lists whoever is signed in, not whoever signed up" do
    Timesheet.create!(person: create_person("Standing"), position: @dirt,
                      on_duty: Time.zone.local(YEAR, 8, 27, 11, 0, 0),
                      additional_notes: "signed in for the test")
    sign_up(create_person("Absentee"), @slot)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(mode: "on-duty", year: YEAR)

    assert_response :success
    assert_select "th[scope=row] a", text: "Standing"
    assert_no_match "Absentee", response.body
    assert_select "th", text: "On Duty"
    assert_select "th", text: "Duration"
  end

  test "the scheduled report names the shift's own columns" do
    sign_up(create_person("Dusty"), @slot)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)

    assert_select "th", text: "Shift Start"
    assert_select "th", text: "On Duty", count: 0
  end

  # --- what may be asked about ---

  # Upstream posts the window itself, so any caller can ask for a report over
  # any window at all. Here the only windows are the ones the picker offers.
  test "a shift from another year cannot be picked" do
    sign_up(create_person("Dusty"), @other_year_slot)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @other_year_slot.id)

    assert_response :success
    assert_select "table", false
    assert_no_match "Dusty", response.body
  end

  test "a slot id that is not a shift at all reports nothing" do
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: 0)

    assert_response :success
    assert_select "table", false
  end

  # A bracketed parameter arrives as an Array or as Parameters, neither of which
  # is blank and neither of which answers to_i.
  test "a bracketed slot id is refused rather than raising" do
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR), params: { slot_id: [@slot.id.to_s] }
    assert_response :success

    get scheduling_shift_lead_path(year: YEAR), params: { slot_id: { a: "1" } }
    assert_response :success
    assert_select "table", false
  end

  # The year selector submits its own bare GET, so whatever the page is
  # reporting on has to ride along as hidden fields or changing the year throws
  # it away and lands the reader back on the empty picker.
  test "the year selector carries the picked shift with it" do
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)

    assert_select "form input[type=hidden][name=slot_id][value=?]", @slot.id.to_s, minimum: 1
  end

  test "the year selector carries the live mode with it" do
    sign_in_as(@admin)

    get scheduling_shift_lead_path(mode: "on-duty", year: YEAR)

    assert_select "form input[type=hidden][name=mode][value=on-duty]", minimum: 1
    assert_select "form input[type=hidden][name=slot_id]", false
  end

  # --- the print sheet ---

  # `authorize_role` on this controller carries no `only:`, so the print action
  # is behind the same gate without any second declaration. Asserted rather than
  # assumed, because that is exactly the kind of coverage a later `only:` would
  # silently remove.
  test "the print sheet is behind the same gate" do
    sign_in_as(@outsider)

    get scheduling_shift_lead_print_path(year: YEAR, slot_id: @slot.id)

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "the print sheet puts the picked shift's roster on paper" do
    sign_up(create_person("Dusty"), @slot)
    sign_in_as(@admin)

    get scheduling_shift_lead_print_path(year: YEAR, slot_id: @slot.id)

    assert_response :success
    assert_select "section.shift-lead-sheet"
    assert_select ".sheet-mode", text: /SCHEDULED/
    assert_select "td span.sheet-callsign", text: "Dusty"
    assert_select ".sheet-legend-title", text: "Decoder ring"
  end

  # The sheet is the page: no navbar, no sidebar, and no picker to change what
  # it is reporting on.
  test "the print sheet renders through the chrome-free layout" do
    sign_up(create_person("Dusty"), @slot)
    sign_in_as(@admin)

    get scheduling_shift_lead_print_path(year: YEAR, slot_id: @slot.id)

    assert_select "#sidebar-drawer", false
    assert_select "select#slot_id", false
  end

  # A named @page rule, never the bare one in layouts/print -- that one reaches
  # every print view in the app, including the sign-up sheet, which carries no
  # page numbers on purpose.
  test "the print sheet emits its page rules on a named rule" do
    sign_up(create_person("Dusty"), @slot)
    sign_in_as(@admin)

    get scheduling_shift_lead_print_path(year: YEAR, slot_id: @slot.id)

    assert_match "@page shift-lead-sheet", response.body
    assert_match "size: letter portrait", response.body
  end

  test "the print sheet reports whoever is on duty when asked for the live one" do
    Timesheet.create!(person: create_person("Standing"), position: @dirt,
                      on_duty: Time.zone.local(YEAR, 8, 27, 11, 0, 0),
                      additional_notes: "signed in for the test")
    sign_in_as(@admin)

    get scheduling_shift_lead_print_path(mode: "on-duty", year: YEAR)

    assert_response :success
    assert_select ".sheet-mode", text: /ON DUTY/
    assert_select "td span.sheet-callsign", text: "Standing"
    assert_select "th", text: "On duty"
  end

  # A blank sheet is not a document.
  test "printing with nothing picked goes back to the picker" do
    sign_in_as(@admin)

    get scheduling_shift_lead_print_path(year: YEAR)

    assert_redirected_to scheduling_shift_lead_path(year: YEAR)
  end

  test "the report links to its own print sheet, carrying what it is showing" do
    sign_up(create_person("Dusty"), @slot)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)

    assert_select "a[href=?]", scheduling_shift_lead_print_path(year: YEAR, slot_id: @slot.id)
  end

  # --- filtering ---

  # Every filter narrows the three rosters and nothing else. The headline
  # numbers and the shortfall list describe the shift, not the reader's current
  # view of it: a position is short whether or not the reader is looking at
  # Green Dots.
  test "a filter narrows the rosters but not the headline numbers" do
    create_ranger("Veteran", years: [2015, 2016, 2017, 2018, 2019, 2020])
    create_ranger("Sophomore", years: [2024])
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id, years: "5")

    assert_response :success
    assert_select "#shift-lead-dirt th[scope=row] a", text: "Veteran"
    assert_select "#shift-lead-dirt th[scope=row] a", text: "Sophomore", count: 0
    # 2 Dirt Rangers on the shift, not the 1 that survived the filter.
    assert_select "[aria-label='Shift summary']", text: /2\s*Dirt Rangers/
  end

  test "the gender filter offers only the codes the roster holds" do
    create_ranger("Fern", gender: Gender::GENDER_CIS_FEMALE)
    create_ranger("Morris", gender: Gender::GENDER_MALE)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id, gender: "F")

    assert_select "#shift-lead-dirt th[scope=row] a", text: "Fern"
    assert_select "#shift-lead-dirt th[scope=row] a", text: "Morris", count: 0
    assert_select "select[name=gender] option[value=F]", text: "F (1)"
    assert_select "select[name=gender] option[value=NB]", count: 0
  end

  # One control for both vehicle columns, because they answer one question.
  test "the vehicle filter reaches both columns and the blacklist" do
    create_ranger("Hauler", motorpool: true, insurance: true)
    create_ranger("Signer", motorpool: true)
    create_ranger("Banned", motorpool: true, blacklisted: true)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id, vehicle: "both")
    assert_select "#shift-lead-dirt th[scope=row] a", text: "Hauler"
    assert_select "#shift-lead-dirt th[scope=row] a", text: "Signer", count: 0

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id, vehicle: "blacklisted")
    assert_select "#shift-lead-dirt th[scope=row] a", text: "Banned"
    assert_select "#shift-lead-dirt th[scope=row] a", text: "Hauler", count: 0
  end

  # The option label and the filter value are the position's FULL title: the
  # roster column abbreviates because it is narrow, but a select is where the
  # reader chooses rather than reads, and "GDLead" needs the decoder ring.
  test "the position filter is named and matched by the full title" do
    create_ranger("Dusty")
    wrench = create_person("Wrench")
    PersonPosition.create!(person: wrench, position: @troubleshooter)
    sign_up(wrench, create_slot(@troubleshooter, begins: @slot.begins, ends: @slot.ends))
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id, position: "Troubleshooter")

    assert_select "th[scope=row] a", text: "Wrench"
    assert_select "th[scope=row] a", text: "Dusty", count: 0
    assert_select "select[name=position] option[value=?]", "Troubleshooter", text: "Troubleshooter (1)"
    # The short title is what the roster column prints, and only that.
    assert_select "select[name=position] option[value=TShoot]", count: 0
    assert_select "#shift-lead-filters", text: /Position: Troubleshooter/
  end

  # A position lives on exactly one roster, so the other two could only ever say
  # "0 of N -- no one matches". Two panels of noise around the one answer.
  test "filtering by position collapses the page to that position's roster" do
    create_ranger("Dusty")
    wrench = create_person("Wrench")
    PersonPosition.create!(person: wrench, position: @troubleshooter)
    sign_up(wrench, create_slot(@troubleshooter, begins: @slot.begins, ends: @slot.ends))
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id, position: "Troubleshooter")

    assert_select "#shift-lead-dirt", false
    assert_select "#shift-lead-command", false
    assert_select "#shift-lead-special"
  end

  # Chosen by where the position lives in the unfiltered report, not by which
  # list still has rows -- a second filter can empty every one of them, and the
  # reader still needs to see which roster they were asking about.
  test "the position's roster is still shown when another filter empties it" do
    # Fern makes F a gender the report holds, so the filter survives validation;
    # Wrench is the only Troubleshooter and is not F, so Special Teams empties.
    create_ranger("Fern", gender: Gender::GENDER_CIS_FEMALE)
    wrench = create_person("Wrench")
    wrench.update!(gender_identity: Gender::GENDER_MALE)
    PersonPosition.create!(person: wrench, position: @troubleshooter)
    sign_up(wrench, create_slot(@troubleshooter, begins: @slot.begins, ends: @slot.ends))
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id,
                                         position: "Troubleshooter", gender: "F")

    assert_select "#shift-lead-special", text: /No one on this roster matches the current filters/
    assert_select "#shift-lead-dirt", false
  end

  test "all three rosters are shown when no position is chosen" do
    create_ranger("Dusty")
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)

    assert_select "#shift-lead-dirt"
    assert_select "#shift-lead-command"
    assert_select "#shift-lead-special"
  end

  test "the shift start filter narrows to one sign-up window" do
    create_ranger("Noon")
    early_slot = create_slot(@green_dot, begins: Time.zone.local(YEAR, 8, 27, 11, 0, 0),
                             ends: Time.zone.local(YEAR, 8, 27, 17, 0, 0))
    sign_up(create_person("Early"), early_slot)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id, start_time: "11:00")

    assert_select "#shift-lead-dirt th[scope=row] a", text: "Early"
    assert_select "#shift-lead-dirt th[scope=row] a", text: "Noon", count: 0
  end

  # There is no sign-up to have a start time on the live report, so the filter
  # is forced off rather than silently emptying every roster.
  test "the shift start filter is not offered on the live report" do
    Timesheet.create!(person: create_person("Standing"), position: @dirt,
                      on_duty: Time.zone.local(YEAR, 8, 27, 11, 0, 0),
                      additional_notes: "signed in for the test")
    sign_in_as(@admin)

    get scheduling_shift_lead_path(mode: "on-duty", year: YEAR, start_time: "11:45")

    assert_response :success
    assert_select "select[name=start_time]", false
    assert_select "th[scope=row] a", text: "Standing"
    # The roster surviving is not enough on its own -- an on-duty row carries no
    # `begins`, so a start_time that got through would match nothing and empty
    # it. Assert the filter was dropped rather than applied: no chip claims to
    # be narrowing, and the URLs the page builds carry no start_time.
    assert_select "#shift-lead-filters a[aria-label*=?]", "Shift Start", count: 0
    assert_select "a[href*=start_time]", count: 0
  end

  # A stale bookmark naming a position no one is standing would otherwise empty
  # every roster while its chip claimed to be narrowing something.
  test "a filter value the roster does not hold is ignored" do
    create_ranger("Dusty")
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id, position: "NoSuchPosition")

    assert_select "#shift-lead-dirt th[scope=row] a", text: "Dusty"
    assert_select "#shift-lead-filters a[aria-label^=?]", "Remove filter", count: 0
  end

  # A roster filtered down to no one and a roster no one signed up for want
  # different things done about them, so they do not share a message.
  test "a roster filtered to no one says so rather than claiming it is empty" do
    create_ranger("Sophomore", years: [2024])
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id, years: "10")

    assert_select "#shift-lead-dirt", text: /No one on this roster matches the current filters/
    assert_select "#shift-lead-dirt", text: /No one has signed up/, count: 0
    assert_select "#shift-lead-dirt", text: /0 of 1/
  end

  # Chips, clear-all and the Print button all rebuild the URL, and every one of
  # them has to carry the shift, the year and any sort or the reader lands back
  # on the empty picker in default order.
  test "removing a chip keeps the shift and the sorts" do
    create_ranger("Dusty", years: [2024])
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id, years: "1",
                                         gender: "F", sort_dirt: "callsign")

    assert_select "#shift-lead-filters a[aria-label=?]", "Remove filter: Years: 1 or more years" do |links|
      url = links.first["href"]
      assert_includes url, "slot_id=#{@slot.id}"
      assert_includes url, "year=#{YEAR}"
      assert_includes url, "sort_dirt=callsign"
      assert_not_includes url, "years="
    end
  end

  # --- sorting ---

  test "each roster carries its own sort and they do not disturb each other" do
    create_green_dot("Zephyr")
    create_ranger("Anvil")
    ts_slot = create_slot(@troubleshooter, begins: @slot.begins, ends: @slot.ends)
    # Different years, so Special Teams' own order is years-descending and a
    # callsign sort leaking across from the dirt roster would reverse it.
    { "Wrench" => [2015, 2016, 2017], "Spanner" => [2024] }.each do |callsign, years|
      person = create_person(callsign, years: years)
      PersonPosition.create!(person: person, position: @troubleshooter)
      sign_up(person, ts_slot)
    end
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id, sort_dirt: "callsign")

    assert_response :success
    assert_select "select#sort_dirt option[selected][value=callsign]"
    # The other roster keeps the report's own order: one control, one roster.
    assert_select "select#sort_special option[selected][value=default]"
    assert_equal ["Anvil", "Zephyr"], roster_callsigns("#shift-lead-dirt")
    assert_equal ["Wrench", "Spanner"], roster_callsigns("#shift-lead-special")
  end

  # Greenie is on the Green Dot slot, so the report's own order puts them FIRST
  # (position title descending, "GD" after "Dirt") despite having the fewest
  # years. Without that the default order is already years-descending and this
  # assertion would pass with the sort deleted.
  test "sorting by years puts the most experienced first" do
    create_green_dot("Greenie", years: [2024])
    create_ranger("Salt", years: [2015, 2016, 2017])
    create_ranger("Middle", years: [2020, 2021])
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)
    assert_equal ["Greenie", "Salt", "Middle"], roster_callsigns("#shift-lead-dirt"),
                 "the report's own order should differ from the years order, or this proves nothing"

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id, sort_dirt: "years")

    assert_equal ["Salt", "Middle", "Greenie"], roster_callsigns("#shift-lead-dirt")
  end

  test "sorting by callsign overrides the report's position order" do
    create_green_dot("Zephyr")
    create_ranger("Anvil")
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)
    assert_equal ["Zephyr", "Anvil"], roster_callsigns("#shift-lead-dirt")

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id, sort_dirt: "callsign")

    assert_equal ["Anvil", "Zephyr"], roster_callsigns("#shift-lead-dirt")
  end

  # Blank genders last rather than first: an unstated gender is the absence of
  # the thing being sorted on, not the lowest value of it.
  test "sorting by gender puts the unstated ones last" do
    create_ranger("Anvil", gender: Gender::GENDER_MALE)
    create_ranger("Bramble")
    create_ranger("Cinder", gender: Gender::GENDER_CIS_FEMALE)
    sign_in_as(@admin)

    # All three share a position, a start time and no years, so the report falls
    # through to callsign ascending -- which the gender order must differ from,
    # or the assertion below would hold with the sort branch deleted.
    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)
    assert_equal ["Anvil", "Bramble", "Cinder"], roster_callsigns("#shift-lead-dirt")

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id, sort_dirt: "gender")

    assert_equal ["Cinder", "Anvil", "Bramble"], roster_callsigns("#shift-lead-dirt")
  end

  # The default is the report's own order, so naming it in the URL says nothing
  # and would put three dead parameters on every chip and the Print button.
  test "a roster left in its default order is not named in the URL" do
    create_ranger("Dusty")
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id, sort_dirt: "callsign")

    assert_select "a[href*=?]", "sort_dirt=callsign"
    assert_select "a[href*=?]", "sort_command", count: 0
    # "all" is the filter bar's sentinel and is not a sort; an unset sort is the
    # report's own order.
    assert_select "a[href*=?]", "sort_dirt=all", count: 0
  end

  test "the print sheet carries the filters and names them on the paper" do
    create_ranger("Veteran", years: [2015, 2016, 2017, 2018, 2019, 2020])
    create_ranger("Sophomore", years: [2024])
    sign_in_as(@admin)

    get scheduling_shift_lead_print_path(year: YEAR, slot_id: @slot.id, years: "5")

    assert_response :success
    assert_select "td span.sheet-callsign", text: "Veteran"
    assert_select "td span.sheet-callsign", text: "Sophomore", count: 0
    # A sheet quietly holding fewer people than the shift does would be the
    # worst kind of wrong, so it says what was left out.
    assert_select ".sheet-filters", text: /Years: 5 or more years/
  end

  # `?mode[x]=1` hands the page an ActionController::Parameters that survives
  # `.presence` and then raises UnfilteredParameters the moment a route helper
  # calls to_query on it. The sibling slot_id parameter is hardened the same way.
  test "a bracketed mode parameter is refused rather than raising" do
    create_ranger("Dusty")
    sign_in_as(@admin)

    get "/scheduling/shift-lead?year=#{YEAR}&slot_id=#{@slot.id}&mode%5Bx%5D=1"
    assert_response :success

    get "/scheduling/shift-lead?year=#{YEAR}&slot_id=#{@slot.id}&mode%5B%5D=on-duty"
    assert_response :success
    # Whatever the query string said, only the resolved mode reaches a URL.
    assert_select "a[href*=?]", "mode=%5B", count: 0
  end

  # fa_icon is aria-hidden and a title: on a span with text is not announced, so
  # a bare "GTR" on both branches leaves the yes/no to colour alone -- and below
  # lg this block is the only rendering of the roster.
  test "the phone roster says the vehicle answer in words" do
    create_ranger("Signer", motorpool: true)
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)

    assert_select "#shift-lead-dirt .lg\\:hidden span.badge", text: "GTR"
    assert_select "#shift-lead-dirt .lg\\:hidden span.badge", text: "No VEH"
  end

  # A shift no one signed up for is not a filter miss, and blaming the filters
  # sends the reader hunting for one to clear that was never set.
  test "an empty shift is not reported as a filter miss" do
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)

    assert_select "#shift-lead-filters", text: /No one has signed up for this shift/
    assert_select "#shift-lead-filters", text: /current filters/, count: 0
  end

  # A count has to promise the roster the choice delivers. Counting against the
  # whole report instead advertises a number the other filters have already
  # taken away.
  test "filter counts are taken against the other filters in force" do
    create_ranger("Fern", gender: Gender::GENDER_CIS_FEMALE, years: [2024])
    create_ranger("Salt", gender: Gender::GENDER_MALE, years: [2015, 2016, 2017, 2018, 2019])
    sign_in_as(@admin)

    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id)
    assert_select "select[name=gender] option", text: "F (1)"

    # Fern has one year, so under "5 or more" the F option can only deliver
    # no one -- and an option that can only return an empty roster is not shown.
    get scheduling_shift_lead_path(year: YEAR, slot_id: @slot.id, years: "5")
    assert_select "select[name=gender] option", text: "F (1)", count: 0
    assert_select "select[name=gender] option", text: "M (1)"
  end

  # All three rosters share an identical ten-column header, so a continuation
  # sheet is unattributable unless the roster's name repeats with the thead.
  test "the print sheet repeats each roster's name inside its table head" do
    create_ranger("Dusty")
    sign_in_as(@admin)

    get scheduling_shift_lead_print_path(year: YEAR, slot_id: @slot.id)

    assert_select "thead tr.sheet-running-head th", text: /DIRT \/ GREEN DOTS/
  end

  test "the print sheet's return link carries the filters and sorts back" do
    create_ranger("Fern", gender: Gender::GENDER_CIS_FEMALE)
    sign_in_as(@admin)

    get scheduling_shift_lead_print_path(year: YEAR, slot_id: @slot.id,
                                               gender: "F", sort_dirt: "callsign")

    assert_select "a[href*=?]", "gender=F"
    assert_select "a[href*=?]", "sort_dirt=callsign"
  end

  private

  def sign_up(person, slot) = PersonSlot.create!(person:, slot:)

  # One signed-up Ranger on @slot, with whatever the test needs to filter on.
  # A Green Dot sign-up on the same window, so a roster holds two position
  # titles. Every sort test needs that: with one position and one start time the
  # report's own comparator falls straight through to years then callsign, and
  # an expectation written in that order passes whether or not the sort ran.
  def create_green_dot(callsign, years: [])
    @gd_slot ||= create_slot(@green_dot, begins: @slot.begins, ends: @slot.ends)
    person = create_person(callsign, years: years)
    sign_up(person, @gd_slot)
    person
  end

  def create_ranger(callsign, years: [], gender: nil, motorpool: false, insurance: false, blacklisted: false)
    person = create_person(callsign, years: years)
    person.update!(gender_identity: gender) if gender
    person.update!(vehicle_blacklisted: true) if blacklisted

    if motorpool || insurance
      PersonEvent.create!(person_id: person.id, year: YEAR,
                          signed_motorpool_agreement: motorpool, org_vehicle_insurance: insurance)
    end

    sign_up(person, @slot)
    person
  end

  # The callsigns of one roster's desktop table, in the order it renders them.
  def roster_callsigns(selector)
    css_select("#{selector} .hidden.lg\\:block tbody th[scope=row] a").map { |link| link.text.strip }
  end
end
