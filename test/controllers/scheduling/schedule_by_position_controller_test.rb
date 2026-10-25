# frozen_string_literal: true

require "test_helper"

# The Schedule by Position report: its gate, its position list, and one
# position's shifts.
class Scheduling::ScheduleByPositionControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper   # create_slot
  include PersonTestFactory        # create_person
  include DomIdTestHelper          # assert_unique_dom_ids

  # A year the fixtures leave alone.
  YEAR = 2022
  DENY_MESSAGE = "Admin, Edit Slots, or Event Management role required " \
                 "to view the schedule by position."

  setup do
    Rails.cache.clear
    Current.reset

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::EDIT_SLOTS, "Edit Slots")
    ensure_role(Role::VC, "Volunteer Coordinator")

    @admin = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    # Edit Slots reads this report but is NOT in PersonConcern::VIEW_ROLES, so
    # the callsigns on it cannot be links for them.
    @slot_editor = person(:retired_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
    grant_role(@slot_editor, Role::EDIT_SLOTS)
    grant_role(@outsider, Role::VC)

    @dirt = positions(:ood_position)
    @other_position = positions(:khaki_supervisor)
    @retired_position = positions(:council_manager)
    @retired_position.update!(active: false)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def august(day, hour = 12, year: YEAR)
    Time.zone.local(year, 8, day, hour, 0, 0)
  end

  # A shift. Slot options pass straight through, so a test can set description,
  # active, max and so on without this helper having to name each one.
  def shift(position: @dirt, begins: august(25), hours: 6, **options)
    create_slot(position, begins:, ends: begins + hours.hours, **options)
  end

  def sign_up(person, slot)
    PersonSlot.create!(person:, slot:)
    slot
  end

  # One stat box's rendered text ("3Shifts"), found by its label. The value and
  # the label are adjacent divs inside the box, so they arrive concatenated.
  def stat_box(label)
    css_select("div.rounded-lg.text-center").map { |el| el.text.squish }
                                            .find { |text| text.end_with?(label) }
  end

  # The index rows, in the order the page lists them. Title and meta live in the
  # same anchor, so a row's text ties a position to its own figures.
  def index_rows
    css_select("a[href*='schedule-by-position/position/']")
  end

  def index_titles
    index_rows.map { |row| row.text.squish[/\A[^•]+/].to_s.strip }
  end

  # Anchored on the "?" that follows the id: a bare substring would also match
  # any position whose id merely starts with these digits.
  def index_row_text(position)
    row = index_rows.find { |r| r["href"].include?("/position/#{position.id}?") }
    row&.text&.squish
  end

  # The shift rows of the position page. Time and description share one cell, as
  # they do upstream.
  def shift_cells
    css_select("th[data-label='Time & Description'], td[data-label='Time & Description']")
      .map { |cell| cell.text.squish }
  end

  def callsign_cells
    css_select("td[data-label=Callsigns]").map { |cell| cell.text.squish }
  end

  # --- Authorization ------------------------------------------------------

  # Upstream SlotPolicy's before hook admits Admin and Edit Slots before
  # report() is reached, and report() adds Event Management.
  test "admin, edit slots, and event management may all view the report" do
    [@admin, @slot_editor, @event_manager].each do |viewer|
      sign_in_as(viewer)
      get scheduling_schedule_by_position_path(year: YEAR)
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "a person with neither role is turned away" do
    sign_in_as(@outsider)
    get scheduling_schedule_by_position_path(year: YEAR)
    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "the position page is gated too" do
    sign_in_as(@outsider)
    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_redirected_to me_root_path
  end

  # --- The position list --------------------------------------------------

  test "the index lists one row per position with its shifts, sign-ups, and span" do
    sign_up(@admin, shift(begins: august(25), hours: 6))
    sign_up(@event_manager, shift(begins: august(28), hours: 4))
    shift(position: @other_position, begins: august(27), hours: 3)

    get scheduling_schedule_by_position_path(year: YEAR)
    assert_response :success

    # max is 20 a shift, so two shifts are 40 seats and one is 20.
    assert_equal "#{@dirt.title} • 2 shifts • 2 of 40 signed up • Aug 25 – Aug 28",
                 index_row_text(@dirt)
    assert_equal "#{@other_position.title} • 1 shift • 0 of 20 signed up • Aug 27",
                 index_row_text(@other_position)
  end

  # A shift running past midnight ends on the following day. Bounding the span
  # by when the last shift STARTED would drop that day.
  test "an overnight shift counts the day it ends on" do
    shift(begins: august(28, 22), hours: 8)

    get scheduling_schedule_by_position_path(year: YEAR)
    assert_response :success
    assert_match(/Aug 28 – Aug 29/, index_row_text(@dirt))
  end

  # "%b %-d" carries no year, so two ends a year apart used to read as one day.
  # A shift can begin in December and end in January, and begins_year keeps both
  # under the same year.
  test "a span that crosses new year names the year at both ends" do
    shift(begins: Time.zone.local(YEAR, 1, 1, 9, 0, 0), hours: 4)
    shift(begins: Time.zone.local(YEAR, 12, 31, 22, 0, 0), hours: 5)

    get scheduling_schedule_by_position_path(year: YEAR)
    assert_response :success
    assert_match(/Jan 1, #{YEAR} – Jan 1, #{YEAR + 1}/, index_row_text(@dirt))
  end

  test "only the chosen year is counted" do
    shift(begins: august(25))
    shift(begins: august(25, year: 2019))

    get scheduling_schedule_by_position_path(year: YEAR)
    assert_response :success
    assert_match(/1 shift •/, index_row_text(@dirt))
  end

  test "a position with no shifts this year is not listed" do
    shift(position: @dirt)

    get scheduling_schedule_by_position_path(year: YEAR)
    assert_response :success
    # The row that should be there, as well as the one that should not: on its
    # own the absence also holds when the page lists nothing at all.
    assert_not_nil index_row_text(@dirt)
    assert_nil index_row_text(@other_position)
  end

  test "a year with no shifts says so" do
    get scheduling_schedule_by_position_path(year: YEAR)
    assert_response :success
    assert_select "body", text: /No #{YEAR} shifts were found/
  end

  test "the index is ordered by position title, case-insensitively" do
    lower = Position.create!(title: "aardvark position", type: "Frontline", active: true)
    upper = Position.create!(title: "Baker position", type: "Frontline", active: true)
    shift(position: upper)
    shift(position: lower)

    get scheduling_schedule_by_position_path(year: YEAR)
    assert_response :success

    listed = index_titles
    assert_equal ["aardvark position", "Baker position"],
                 listed & ["aardvark position", "Baker position"]
  end

  test "a retired position is badged on the index" do
    shift(position: @retired_position)

    get scheduling_schedule_by_position_path(year: YEAR)
    assert_response :success
    assert_match(/Inactive/, index_row_text(@retired_position))
  end

  # --- Inactive shifts ----------------------------------------------------

  # Nothing is held back here. A switched-off shift is still on the board, and
  # the position page names it as switched off.
  test "the index counts active and inactive shifts alike" do
    shift(position: @dirt, begins: august(25), active: true)
    shift(position: @dirt, begins: august(26), active: false)
    shift(position: @other_position, active: false)

    get scheduling_schedule_by_position_path(year: YEAR)
    assert_response :success

    assert_equal "#{@dirt.title} • 2 shifts • 0 of 40 signed up • Aug 25 – Aug 26",
                 index_row_text(@dirt)
    # A position holding nothing but switched-off shifts is still listed.
    assert_not_nil index_row_text(@other_position)
  end

  # --- One position's shifts ----------------------------------------------

  test "shifts are listed earliest first" do
    shift(begins: august(28), description: "last")
    shift(begins: august(24), description: "first")
    shift(begins: august(26), description: "middle")

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success

    assert_equal ["first", "middle", "last"],
                 shift_cells.map { |text| text[/first|middle|last/] }
  end

  test "the position page totals shifts, sign-ups, and empty shifts" do
    taken = shift(begins: august(24))
    sign_up(@admin, taken)
    sign_up(@event_manager, taken)
    shift(begins: august(26))

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success

    assert_equal "2Shifts", stat_box("Shifts")
    assert_equal "2 of 40Signed Up", stat_box("Signed Up")
    assert_equal "1Empty Shifts", stat_box("Empty Shifts")
  end

  # A hand-typed URL must not read past the year the rest of the page describes.
  test "another year's shifts stay off the position page" do
    shift(begins: august(25), description: "this year")
    shift(begins: august(25, year: 2019), description: "other year")

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_equal ["this year"], shift_cells.map { |text| text[/this year|other year/] }
  end

  test "sign-ups are listed in callsign order" do
    slot = shift
    sign_up(create_person("Zebra"), slot)
    sign_up(create_person("Aardvark"), slot)

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_equal ["Aardvark, Zebra"], callsign_cells
  end

  # On a coverage report an empty shift is the finding, not a blank cell.
  test "a shift no one signed up for says so" do
    shift

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_equal ["No sign-ups"], callsign_cells
  end

  test "a shift with no description reads as absent" do
    shift(description: nil)

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_match(/—/, shift_cells.first)
  end

  # The stat box is a call to action, so it counts only gaps somebody can close.
  # A switched-off shift cannot be signed up for, and a shift whose sub-shift is
  # staffed is covered -- the row says so two columns over.
  test "empty shifts counts only active shifts no one is covering" do
    shift(begins: august(20), active: true)                          # a real gap
    sign_up(@admin, shift(begins: august(21), active: true))         # taken
    shift(begins: august(22), active: false)                         # cannot be taken

    parent = shift(begins: august(23), active: true)
    sign_up(create_person("Subshifter"),
            shift(position: @other_position, begins: august(23),
                  parent_signup_slot_id: parent.id))                 # covered by its sub-shift

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success

    assert_equal "4Shifts", stat_box("Shifts")
    assert_equal "1Empty Shifts", stat_box("Empty Shifts")
    # The covered parent still reads "No sign-ups" in its own column -- the
    # people are on the sub-shift, and the row names them right beneath.
    assert_match(/1 sign-up in the #{Regexp.escape(@other_position.title)} sub-shift/,
                 callsign_cells.last)
  end

  # The Status column is what tells the two apart, so the shift itself is
  # listed either way.
  test "an inactive shift is listed and badged rather than hidden" do
    shift(begins: august(24), active: true, description: "open")
    shift(begins: august(26), active: false, description: "switched off")

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success

    assert_equal ["open", "switched off"],
                 shift_cells.map { |text| text[/open|switched off/] }
    assert_equal "2Shifts", stat_box("Shifts")
    assert_select "td", text: /Inactive/
  end

  test "a position with no shifts this year gets an empty state, not a blank table" do
    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_select "body", text: /#{Regexp.escape(@dirt.title)} has no #{YEAR} shifts/
  end

  test "an unknown position is sent back to the list" do
    get scheduling_schedule_by_position_position_path(0, year: YEAR)
    assert_redirected_to scheduling_schedule_by_position_path(year: YEAR)
    assert_equal Scheduling::ScheduleByPositionController::POSITION_NOT_FOUND,
                 flash[:error]
  end

  # --- Linked shifts ------------------------------------------------------

  # A shift that feeds a bigger one: whoever is on the parent is covering the
  # same hours, so the page names them.
  test "the parent shift's sign-ups are listed beneath the shift" do
    parent = shift(position: @other_position, begins: august(25))
    sign_up(create_person("Parentcallsign"), parent)
    shift(position: @dirt, begins: august(25), parent_signup_slot_id: parent.id)

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success

    assert_match(/1 sign-up in the parent #{Regexp.escape(@other_position.title)} shift/,
                 callsign_cells.first)
    assert_match(/Parentcallsign/, callsign_cells.first)
  end

  test "an empty parent shift says no one is on it" do
    parent = shift(position: @other_position, begins: august(25))
    shift(position: @dirt, begins: august(25), parent_signup_slot_id: parent.id)

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_match(/No one has signed up for the parent #{Regexp.escape(@other_position.title)} shift/,
                 callsign_cells.first)
  end

  test "the sub-shift's sign-ups are listed beneath the shift" do
    parent = shift(position: @dirt, begins: august(25))
    child = shift(position: @other_position, begins: august(25),
                  parent_signup_slot_id: parent.id)
    sign_up(create_person("Childcallsign"), child)

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success

    assert_match(/1 sign-up in the #{Regexp.escape(@other_position.title)} sub-shift/,
                 callsign_cells.first)
    assert_match(/Childcallsign/, callsign_cells.first)
  end

  # Positions in a lineup run the same hours under different names, so the
  # partner's shift is matched by when it starts rather than by any link.
  test "a lineup partner's shift running alongside is listed beneath the shift" do
    lineup = PositionLineup.create!(description: "Test lineup")
    PositionLineupMember.create!(position_lineup: lineup, position: @dirt)
    PositionLineupMember.create!(position_lineup: lineup, position: @other_position)

    partner = shift(position: @other_position, begins: august(25, 12) + 30.minutes)
    sign_up(create_person("Partnercallsign"), partner)
    shift(position: @dirt, begins: august(25, 12))

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success

    assert_match(/1 sign-up in the corresponding #{Regexp.escape(@other_position.title)} shift/,
                 callsign_cells.first)
    assert_match(/Partnercallsign/, callsign_cells.first)
  end

  # Candidates are filed by the hour they start, and a partner exactly an hour
  # out lands in a neighbouring bucket. Both edges are tested: reading only the
  # bucket ahead would drop every partner starting in the hour before.
  test "a lineup partner shift at either edge of the window is still matched" do
    lineup = PositionLineup.create!(description: "Test lineup")
    PositionLineupMember.create!(position_lineup: lineup, position: @dirt)
    PositionLineupMember.create!(position_lineup: lineup, position: @other_position)

    # An hour after the first shift, an hour before the second. Six hours apart,
    # so neither partner is anywhere near the other shift.
    sign_up(create_person("Latecallsign"), shift(position: @other_position, begins: august(25, 13)))
    sign_up(create_person("Earlycallsign"), shift(position: @other_position, begins: august(25, 17)))
    shift(position: @dirt, begins: august(25, 12))
    shift(position: @dirt, begins: august(25, 18))

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success

    assert_match(/Latecallsign/, callsign_cells.first, "a partner an hour later is in the window")
    assert_match(/Earlycallsign/, callsign_cells.last, "a partner an hour earlier is in the window")
  end

  test "a lineup partner with no shift nearby says no one is on it" do
    lineup = PositionLineup.create!(description: "Test lineup")
    PositionLineupMember.create!(position_lineup: lineup, position: @dirt)
    PositionLineupMember.create!(position_lineup: lineup, position: @other_position)

    # Three hours out is well past the hour either side upstream allows.
    sign_up(create_person("Toofarcallsign"),
            shift(position: @other_position, begins: august(25, 15)))
    shift(position: @dirt, begins: august(25, 12))

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success

    assert_match(/No one has signed up for the corresponding/, callsign_cells.first)
    assert_no_match(/Toofarcallsign/, callsign_cells.first)
  end

  # An inactive partner shift is not the one being covered.
  test "an inactive lineup partner shift is not matched" do
    lineup = PositionLineup.create!(description: "Test lineup")
    PositionLineupMember.create!(position_lineup: lineup, position: @dirt)
    PositionLineupMember.create!(position_lineup: lineup, position: @other_position)

    sign_up(create_person("Offcallsign"),
            shift(position: @other_position, begins: august(25, 12), active: false))
    shift(position: @dirt, begins: august(25, 12))

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success
    # The positive half matters: assert_no_match also passes against an empty
    # cell, so on its own it would hold if the block stopped rendering at all.
    assert_match(/No one has signed up for the corresponding/, callsign_cells.first)
    assert_no_match(/Offcallsign/, callsign_cells.first)
  end

  # --- Callsign links -----------------------------------------------------

  # Edit Slots reads this report but is not in PersonConcern::VIEW_ROLES, so
  # every callsign on it would be a link that bounces them to /me.
  test "callsigns are plain text for a reader who cannot open person pages" do
    sign_up(@event_manager, shift)

    sign_in_as(@slot_editor)
    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_match(/#{Regexp.escape(@event_manager.callsign)}/, callsign_cells.first)
    assert_select "td[data-label=Callsigns] a", count: 0

    sign_in_as(@admin)
    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_select "td[data-label=Callsigns] a[href=?]", person_path(@event_manager)
  end

  # The slots admin admits Admin and Edit Slots but not Event Management, who
  # read this report too. The button has to ask that page rather than assume.
  test "the manage slots button is only offered to readers who can open it" do
    shift

    sign_in_as(@event_manager)
    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_select "a[href=?]", scheduling_slots_position_path(@dirt.id, year: YEAR), count: 0

    [@admin, @slot_editor].each do |viewer|
      sign_in_as(viewer)
      get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
      assert_select "a[href=?]", scheduling_slots_position_path(@dirt.id, year: YEAR),
                    { count: 1 }, "#{viewer.callsign} manages slots and should be offered the link"
    end
  end

  # Duplicate ids let Turbo replace the wrong node, and the anchors the jump
  # list targets are ids this page mints per row.
  test "both pages render unique dom ids" do
    sign_up(@admin, shift(begins: august(24)))
    shift(position: @other_position, begins: august(25))

    get scheduling_schedule_by_position_path(year: YEAR)
    assert_response :success
    assert_unique_dom_ids

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_unique_dom_ids
  end

  # --- Timezones ----------------------------------------------------------

  # MIN()/MAX() are expressions Rails has no column type for, so without
  # in_time_zone they come back as bare Times in the HOST's zone, while
  # slot.begins is cast into Time.zone.
  #
  # The assertion is on the ZONE, because the two obvious ones cannot catch it.
  # Comparing the values as instants always passes -- they are the same instant,
  # only labelled differently -- and comparing rendered dates passes on any host
  # whose offset matches Time.zone's, which includes a UTC runner. The zone is
  # the only part that is wrong on every machine.
  test "an aggregated date is read in the app's zone, not the host's" do
    slot = shift(begins: Time.zone.local(YEAR, 2, 17, 0, 30, 0), hours: 4)

    row = ScheduleByPositionReport.index(year: YEAR).find { |r| r.position_id == @dirt.id }
    assert_kind_of ActiveSupport::TimeWithZone, row.tally.first_begins
    assert_equal Time.zone.name, row.tally.first_begins.time_zone.name
    assert_kind_of ActiveSupport::TimeWithZone, row.tally.last_ends
    assert_equal Time.zone.name, row.tally.last_ends.time_zone.name
    # The value is right as well as the zone.
    assert_equal slot.reload.begins, row.tally.first_begins
  end

  # And the same shift renders the same day on both pages. Host-dependent on its
  # own -- it only bites where the host's offset differs from Time.zone's -- so
  # it backs up the zone assertions above rather than standing in for them.
  test "the index and the position page name the same day for a shift near midnight" do
    shift(begins: Time.zone.local(YEAR, 2, 17, 0, 30, 0), hours: 4)

    get scheduling_schedule_by_position_path(year: YEAR)
    index_day = index_row_text(@dirt)[/\w{3} \d+/]

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR)
    page_day = shift_cells.first[/\w{3} \d+/]

    assert_equal index_day, page_day
  end

  # --- CSV ----------------------------------------------------------------

  test "a position exports one row per shift" do
    slot = shift(begins: august(25), hours: 6, description: "Playa")
    sign_up(create_person("Zebra"), slot)
    sign_up(create_person("Aardvark"), slot)

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR,
                                                            format: :csv)
    assert_response :success

    lines = response.body.split("\n")
    assert_equal "Position,Description,From,To,Active,Sign-Ups,Max,Callsigns", lines.first
    # The whole line: a prefix match would pass whether or not the timestamp
    # columns were emitted at all.
    assert_equal [@dirt.title, "Playa", august(25).iso8601, (august(25) + 6.hours).iso8601,
                  "Y", 2, 20, '"Aardvark, Zebra"'].join(","),
                 lines[1]
  end

  # The export carries what the page shows, switched-off shifts included. The
  # Active column is how a spreadsheet tells them apart.
  test "the export carries every shift the page shows" do
    shift(begins: august(24), active: true, description: "open")
    shift(begins: august(26), active: false, description: "switched off")

    get scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR,
                                                            format: :csv)
    assert_response :success

    lines = response.body.split("\n")
    assert_equal 3, lines.size
    assert_match(/open,.*,Y,/, lines[1])
    assert_match(/switched off,.*,N,/, lines[2])
  end

  # --- Year handling ------------------------------------------------------

  test "a year below the floor falls back to the current year" do
    get scheduling_schedule_by_position_path(year: 2007)
    assert_response :success
    assert_select "body", text: /#{Current.year} Schedule by Position/
  end
end
