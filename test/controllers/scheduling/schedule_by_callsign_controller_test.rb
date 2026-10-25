# frozen_string_literal: true

require "test_helper"

# The Schedule by Callsign report: its gate, its roster, and one person's shifts.
class Scheduling::ScheduleByCallsignControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper   # create_slot
  include PersonTestFactory        # create_person

  # A year the fixtures leave alone.
  YEAR = 2022
  DENY_MESSAGE = "Admin, Edit Slots, or Event Management role required " \
                 "to view the schedule by callsign."

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
    # the person page has to stay shut to them for anyone not on the roster.
    @slot_editor = person(:retired_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
    grant_role(@slot_editor, Role::EDIT_SLOTS)
    grant_role(@outsider, Role::VC)

    @dirt = positions(:ood_position)
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

  # One stat box's rendered text ("3Shifts"), found by its label. The value and
  # the label are adjacent divs inside the box, so they arrive concatenated.
  def stat_box(label)
    css_select("div.rounded-lg.text-center").map { |el| el.text.squish }
                                            .find { |text| text.end_with?(label) }
  end

  # A sign-up: the slot plus the person on it. Slot options pass straight
  # through, so a test can set description, active, max and so on without this
  # helper having to name each one.
  def sign_up(person, position: @dirt, begins: august(25), hours: 6, **options)
    slot = create_slot(position, begins:, ends: begins + hours.hours, **options)
    PersonSlot.create!(person:, slot:)
    slot
  end

  # The roster rows, in the order the page lists them. Title and meta live in
  # the same anchor, so a row's text ties a callsign to its own figures.
  def roster_rows
    css_select("a[href*='schedule-by-callsign/person/']")
  end

  def roster_callsigns
    roster_rows.map { |row| row.text.squish[/\A[^•]+/].to_s.strip }
  end

  def roster_row_text(person)
    row = roster_rows.find { |r| r["href"].include?("/person/#{person.id}") }
    row&.text&.squish
  end

  # --- Authorization ------------------------------------------------------

  # Upstream SlotPolicy's before hook admits Admin and Edit Slots before
  # report() is reached, and report() adds Event Management -- the same triple
  # the Flake Report spells off this same policy.
  test "admin, edit slots, and event management may all view the report" do
    [@admin, @slot_editor, @event_manager].each do |viewer|
      sign_in_as(viewer)
      get scheduling_schedule_by_callsign_path(year: YEAR)
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "a person with neither role is turned away" do
    sign_in_as(@outsider)
    get scheduling_schedule_by_callsign_path(year: YEAR)
    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "the person page is gated too" do
    sign_in_as(@outsider)
    get scheduling_schedule_by_callsign_person_path(@admin, year: YEAR)
    assert_redirected_to me_root_path
  end

  # --- The roster ---------------------------------------------------------

  test "the index lists one row per person with their shift count, hours, and span" do
    sign_up(@admin, begins: august(25), hours: 6)
    sign_up(@admin, begins: august(28), hours: 4)
    sign_up(@event_manager, begins: august(27), hours: 3)

    get scheduling_schedule_by_callsign_path(year: YEAR)
    assert_response :success

    assert_select "a", text: /#{@admin.callsign}/
    assert_select "a", text: /2 shifts • 10:00 hrs • Aug 25 – Aug 28/
    assert_select "a", text: /#{@event_manager.callsign}/
    assert_select "a", text: /1 shift • 3:00 hrs • Aug 27/
  end

  # Graveyard shifts are ordinary here. Bounding the span by when the last shift
  # STARTED drops the day it ends on -- and for someone whose only shift runs
  # overnight, claims a one-day presence for two days of it.
  test "an overnight shift counts the day it ends on" do
    sign_up(@admin, begins: august(28, 22), hours: 8)

    get scheduling_schedule_by_callsign_path(year: YEAR)
    assert_response :success
    assert_equal "#{@admin.callsign} • 1 shift • 8:00 hrs • Aug 28 – Aug 29",
                 roster_row_text(@admin)
  end

  # A one-day span reads as one date, not the same date twice.
  test "a single day span is stated once" do
    sign_up(@admin, begins: august(25))

    get scheduling_schedule_by_callsign_path(year: YEAR)
    assert_select "a", text: /Aug 25 – Aug 25/, count: 0
    assert_select "a", text: /1 shift • 6:00 hrs • Aug 25/
  end

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
    slot = sign_up(@admin, begins: Time.zone.local(YEAR, 2, 17, 0, 30, 0), hours: 4)

    row = ScheduleByCallsignReport.summary(year: YEAR).first
    assert_kind_of ActiveSupport::TimeWithZone, row.first_begins
    assert_equal Time.zone.name, row.first_begins.time_zone.name
    assert_kind_of ActiveSupport::TimeWithZone, row.last_ends
    assert_equal Time.zone.name, row.last_ends.time_zone.name
    # The value is right as well as the zone.
    assert_equal slot.reload.begins, row.first_begins
  end

  # The roster and the export button beside it have to name the same day. They
  # did not: the page read the value in Time.zone and the CSV re-read it in the
  # host's zone, which for a shift just past midnight is the day before.
  test "the roster and its CSV name the same day for a shift near midnight" do
    sign_up(@admin, begins: Time.zone.local(YEAR, 2, 17, 0, 30, 0), hours: 4)

    get scheduling_schedule_by_callsign_path(year: YEAR)
    page_day = css_select("a[href*='schedule-by-callsign/person/']").first.text[/\w{3} \d+/]

    get scheduling_schedule_by_callsign_path(year: YEAR, format: :csv)
    csv_day = Time.parse(response.body.split("\n")[1].split(",")[4]).strftime("%b %-d")

    assert_equal page_day, csv_day
  end

  # The same agreement one level down.
  test "the person page and its CSV name the same day for a shift near midnight" do
    sign_up(@admin, begins: Time.zone.local(YEAR, 2, 17, 0, 30, 0), hours: 4)

    get scheduling_schedule_by_callsign_person_path(@admin, year: YEAR)
    page_day = css_select("th[data-label=Time], td[data-label=Time]").first.text[/\w{3} \d+/]

    get scheduling_schedule_by_callsign_person_path(@admin, year: YEAR, format: :csv)
    csv_day = Time.parse(response.body.split("\n")[1].split(",")[2]).strftime("%b %-d")

    assert_equal page_day, csv_day
  end

  test "only the chosen year is counted" do
    sign_up(@admin, begins: august(25), hours: 6)
    sign_up(@admin, begins: august(25, year: 2019), hours: 9)

    get scheduling_schedule_by_callsign_path(year: YEAR)
    assert_response :success
    assert_select "a", text: /1 shift • 6:00 hrs/
    assert_select "a", text: /15:00 hrs/, count: 0
  end

  test "a person with no sign-ups is not listed" do
    sign_up(@admin)

    get scheduling_schedule_by_callsign_path(year: YEAR)
    assert_select "a", text: /#{@event_manager.callsign}/, count: 0
  end

  test "the callsign filter narrows the roster" do
    sign_up(@admin)
    sign_up(@event_manager)

    get scheduling_schedule_by_callsign_path(year: YEAR,
                                                   callsign: @admin.callsign.downcase)
    assert_response :success
    assert_select "a", text: /#{@admin.callsign}/
    assert_select "a", text: /#{@event_manager.callsign}/, count: 0
  end

  test "the status filter narrows the roster" do
    sign_up(@admin)
    sign_up(@event_manager)

    get scheduling_schedule_by_callsign_path(year: YEAR, status: @event_manager.status)
    assert_response :success
    assert_select "a", text: /#{@event_manager.callsign}/
    assert_select "a", text: /#{@admin.callsign}/, count: 0
  end

  # The status select is built from the statuses the roster holds, so a status
  # it does not offer cannot be shown as selected. Left to stand, it would empty
  # the roster while the select beside it still read "All".
  test "a status the roster does not hold is ignored rather than applied" do
    sign_up(@admin)
    sign_up(@event_manager)

    get scheduling_schedule_by_callsign_path(year: YEAR, status: "notastatus")
    assert_response :success

    assert_select "a", text: /#{@admin.callsign}/
    assert_select "a", text: /#{@event_manager.callsign}/
    assert_select "body", text: /Status: notastatus/, count: 0
  end

  test "a filter that matches no one says so rather than claiming the year is empty" do
    sign_up(@admin)

    get scheduling_schedule_by_callsign_path(year: YEAR, callsign: "zzznotacallsign")
    assert_response :success
    assert_select "body", text: /No callsign matches these filters/
    assert_select "body", text: /No #{YEAR} schedules were found/, count: 0
  end

  test "a year with no sign-ups says so" do
    get scheduling_schedule_by_callsign_path(year: YEAR)
    assert_response :success
    assert_select "body", text: /No #{YEAR} schedules were found/
  end

  # --- One person's schedule ----------------------------------------------

  # Upstream's sign-up query carries no ordering, so its table renders in the
  # order the rows were created. This is the fix, and it only shows up when the
  # sign-ups are made out of order.
  test "shifts are listed earliest first even when signed up out of order" do
    sign_up(@admin, begins: august(28), description: "last")
    sign_up(@admin, begins: august(24), description: "first")
    sign_up(@admin, begins: august(26), description: "middle")

    get scheduling_schedule_by_callsign_person_path(@admin, year: YEAR)
    assert_response :success

    assert_equal ["first", "middle", "last"],
                 css_select("td[data-label=Description]").map { |cell| cell.text.strip }
  end

  # Three shifts over two distinct positions: the position count must count the
  # positions, not the shifts.
  test "the person page totals shifts, hours, and distinct positions" do
    sign_up(@admin, position: @dirt, begins: august(24), hours: 6)
    sign_up(@admin, position: @dirt, begins: august(26), hours: 4)
    sign_up(@admin, position: @retired_position, begins: august(28), hours: 2)

    get scheduling_schedule_by_callsign_person_path(@admin, year: YEAR)
    assert_response :success

    assert_equal "3Shifts", stat_box("Shifts")
    assert_equal "12:00Hours", stat_box("Hours")
    assert_equal "2Positions", stat_box("Positions")
  end

  # A hand-typed URL must not read past the year the rest of the page describes.
  test "another year's shifts stay off the person page" do
    sign_up(@admin, begins: august(25), description: "this year")
    sign_up(@admin, begins: august(25, year: 2019), description: "other year")

    get scheduling_schedule_by_callsign_person_path(@admin, year: YEAR)
    assert_response :success
    # Asserted on the description CELL, not the body: the hero reads "Every
    # shift <callsign> signed up for this year", so a body-wide /this year/
    # matches the page chrome and passes even when no row renders at all.
    assert_equal ["this year"],
                 css_select("td[data-label=Description]").map { |cell| cell.text.strip }
  end

  # Scoped to the cell rather than the page: "Inactive" is a person status too,
  # and a page-wide match would pass on the wrong word appearing anywhere.
  test "a retired position is flagged on the person page" do
    sign_up(@admin, position: @retired_position)

    get scheduling_schedule_by_callsign_person_path(@admin, year: YEAR)
    assert_response :success
    assert_select "td", text: /#{Regexp.escape(@retired_position.title)}\s+Inactive/
  end

  test "a shift with no description reads as absent" do
    sign_up(@admin, description: nil)

    get scheduling_schedule_by_callsign_person_path(@admin, year: YEAR)
    assert_response :success
    assert_select "td", text: "—"
  end

  test "a person with no sign-ups this year gets an empty state, not a blank table" do
    get scheduling_schedule_by_callsign_person_path(@event_manager, year: YEAR)
    assert_response :success
    assert_select "body", text: /has no #{YEAR} shift sign-ups/
  end

  # Edit Slots reads this report but is not in PersonConcern::VIEW_ROLES, so
  # /person/:id is shut to them. Rendering a page headed with a callsign for an
  # id they typed would be that page by another name -- and since a person with
  # no sign-ups is not on the roster, it would confirm accounts they cannot
  # otherwise see. Same wording as a missing id, so the two cannot be told apart.
  test "a reader who cannot open person pages cannot confirm a person with no sign-ups" do
    sign_in_as(@slot_editor)

    get scheduling_schedule_by_callsign_person_path(@event_manager, year: YEAR)
    hidden = flash[:error]
    assert_redirected_to scheduling_schedule_by_callsign_path(year: YEAR)

    get scheduling_schedule_by_callsign_person_path(0, year: YEAR)
    assert_equal hidden, flash[:error]
    # Escaped: this is the assertion that the callsign did not leak, and a
    # metacharacter in it would turn an exact check into a fuzzy one that can
    # pass for the wrong reason.
    assert_no_match(/#{Regexp.escape(@event_manager.callsign)}/, hidden.to_s)
  end

  test "a reader who cannot open person pages still sees someone who is on the roster" do
    sign_up(@event_manager)
    sign_in_as(@slot_editor)

    get scheduling_schedule_by_callsign_person_path(@event_manager, year: YEAR)
    assert_response :success
  end

  # Everyone else keeps the empty page: it is true, and bouncing them would
  # break the year selector, which is how a reader asks "did they ranger in
  # 2019?".
  test "a reader who can open person pages still sees an empty year" do
    get scheduling_schedule_by_callsign_person_path(@event_manager, year: YEAR)
    assert_response :success
    assert_select "body", text: /has no #{YEAR} shift sign-ups/
  end

  test "an unknown person is sent back to the roster" do
    get scheduling_schedule_by_callsign_person_path(0, year: YEAR)
    assert_redirected_to scheduling_schedule_by_callsign_path(year: YEAR)
    assert_equal Scheduling::ScheduleByCallsignController::PERSON_NOT_FOUND, flash[:error]
  end

  # --- CSV ----------------------------------------------------------------

  test "the roster exports one row per person" do
    sign_up(@admin, begins: august(25), hours: 6)
    sign_up(@admin, begins: august(28), hours: 4)

    get scheduling_schedule_by_callsign_path(year: YEAR, format: :csv)
    assert_response :success

    lines = response.body.split("\n")
    assert_equal "Callsign,Status,Shifts,Hours,First Shift Begins,Last Shift Ends",
                 lines.first
    # The whole line: a prefix match would pass whether or not the timestamp
    # columns were emitted at all. The dates carry no getlocal, matching what
    # the roster renders -- the agreement tests above pin that directly. The
    # last column is the last shift's END, four hours past its start.
    assert_equal [@admin.callsign, @admin.status, 2, "10.00",
                  august(25).iso8601, (august(28) + 4.hours).iso8601].join(","),
                 lines[1]
  end

  test "a person exports one row per shift" do
    sign_up(@admin, begins: august(25), hours: 6, description: "Playa")

    get scheduling_schedule_by_callsign_person_path(@admin, year: YEAR, format: :csv)
    assert_response :success

    lines = response.body.split("\n")
    assert_equal "Callsign,Status,Shift Begins,Shift Ends,Duration,Description,Position," \
                 "Position Active", lines.first
    assert_equal [@admin.callsign, @admin.status,
                  august(25).iso8601, (august(25) + 6.hours).iso8601,
                  "6.00", "Playa", @dirt.title, "Y"].join(","),
                 lines[1]
  end

  # Whole line, not split(",").last: a description holding a comma shifts every
  # index, and Ruby's split drops trailing empty fields -- so on the row this
  # column is most interesting for (a missing position, which exports blank)
  # `.last` would silently read the column before it.
  test "a retired position exports as not active" do
    sign_up(@admin, position: @retired_position)

    get scheduling_schedule_by_callsign_person_path(@admin, year: YEAR, format: :csv)
    assert_response :success
    assert_equal [@admin.callsign, @admin.status,
                  august(25).iso8601, (august(25) + 6.hours).iso8601,
                  "6.00", "Playa", @retired_position.title, "N"].join(","),
                 response.body.split("\n")[1]
  end

  # --- Roster ordering and badges -----------------------------------------

  # Upstream sorts with strcasecmp. A plain sort_by(&:callsign) would put every
  # capital ahead of every lowercase, so "aardvark" would follow "Baker".
  # GROUP BY returns rows in no guaranteed order, so without the sort this is
  # whatever MariaDB felt like.
  test "the roster is ordered by callsign, case-insensitively" do
    lower = create_person("aardvark")
    upper = create_person("Baker")
    sign_up(upper)
    sign_up(lower)

    get scheduling_schedule_by_callsign_path(year: YEAR)
    assert_response :success

    listed = roster_callsigns
    assert_equal ["aardvark", "Baker"], listed & ["aardvark", "Baker"]
  end

  # Only the exception is badged -- an eight-hundred-row roster reading "Active"
  # on every line is eight hundred chips saying nothing.
  test "a non-active status is badged and an active one is not" do
    sign_up(@admin)          # active
    sign_up(@event_manager)  # echelon

    get scheduling_schedule_by_callsign_path(year: YEAR)
    assert_response :success

    assert_select "a", text: /#{@event_manager.callsign}.*echelon/
    assert_select "a", text: /#{@admin.callsign}.*active/, count: 0
  end

  # Each person's figures have to belong to that person. Four unrelated
  # assertions would all pass if the aggregation attributed each person's
  # totals to the other one.
  test "each roster row carries its own person's figures" do
    sign_up(@admin, begins: august(25), hours: 6)
    sign_up(@admin, begins: august(28), hours: 4)
    sign_up(@event_manager, begins: august(27), hours: 3)

    get scheduling_schedule_by_callsign_path(year: YEAR)
    assert_response :success

    # Anchored end to end: the whole row, badge included, so a figure belonging
    # to the other person cannot hide in an unmatched tail.
    assert_equal "#{@admin.callsign} • 2 shifts • 10:00 hrs • Aug 25 – Aug 28",
                 roster_row_text(@admin)
    assert_equal "#{@event_manager.callsign} • 1 shift • 3:00 hrs • Aug 27 • echelon",
                 roster_row_text(@event_manager)
  end

  # --- Year handling ------------------------------------------------------

  test "a year below the floor falls back to the current year" do
    get scheduling_schedule_by_callsign_path(year: 2007)
    assert_response :success
    assert_select "body", text: /#{Current.year} Schedule by Callsign/
  end
end
