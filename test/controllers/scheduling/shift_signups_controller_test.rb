# frozen_string_literal: true

require "test_helper"

# The Shift Sign-Ups report: its gate, its position list, one position's shifts,
# and both exports.
class Scheduling::ShiftSignupsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper   # create_slot
  include PersonTestFactory        # create_person
  include DomIdTestHelper          # assert_unique_dom_ids
  include ReportCardTestHelper     # assert_report_card

  # A year the fixtures leave alone.
  YEAR = 2022
  DENY_MESSAGE = "Admin, Edit Slots, or Event Management role required " \
                 "to view the shift sign-ups report."

  setup do
    Rails.cache.clear
    Current.reset

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::EDIT_SLOTS, "Edit Slots")
    ensure_role(Role::VC, "Volunteer Coordinator")

    @admin = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @slot_editor = person(:retired_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
    grant_role(@slot_editor, Role::EDIT_SLOTS)
    grant_role(@outsider, Role::VC)

    @dirt = positions(:ood_position)
    @other_position = positions(:khaki_supervisor)

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
  # active, and max without this helper having to name each one.
  def shift(position: @dirt, begins: august(25), hours: 6, **options)
    create_slot(position, begins:, ends: begins + hours.hours, **options)
  end

  # Sign-ups are written the way the rest of the app writes them. slot.signed_up
  # is deliberately left alone -- the report counts these rows, so a test that
  # hand-set the counter would be asserting on its own arithmetic.
  def sign_up(person, slot)
    PersonSlot.create!(person:, slot:)
    slot
  end

  # One index row's cells, by position. Every cell of the row, so a figure is
  # read against the position it belongs to.
  def index_row(position)
    link = css_select("a[href*='shift-signups/position/#{position.id}?']").first
    return nil unless link

    link.ancestors("tr").first.css("th, td").map { |cell| cell.text.squish }
  end

  def index_titles
    css_select("a[href*='shift-signups/position/']").map { |link| link.text.squish }
  end

  # One stat box's rendered text ("3Shifts"), found by its label.
  def stat_box(label)
    css_select("div.rounded-lg.text-center").map { |el| el.text.squish }
                                            .find { |text| text.end_with?(label) }
  end

  def shift_rows
    css_select("tbody tr").map { |row| row.css("th, td").map { |cell| cell.text.squish } }
  end

  # --- Authorization ------------------------------------------------------

  test "admin, edit slots, and event management may all view the report" do
    [@admin, @slot_editor, @event_manager].each do |viewer|
      sign_in_as(viewer)
      get scheduling_shift_signups_path(year: YEAR)
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "a person with neither role is turned away" do
    sign_in_as(@outsider)
    get scheduling_shift_signups_path(year: YEAR)
    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "the position page is gated too" do
    sign_in_as(@outsider)
    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR)
    assert_redirected_to me_root_path
  end

  test "the exports are gated too" do
    sign_in_as(@outsider)
    get scheduling_shift_signups_path(year: YEAR, format: :csv)
    assert_redirected_to me_root_path

    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR, format: :csv)
    assert_redirected_to me_root_path
  end

  # --- The position list --------------------------------------------------

  test "the index lists one row per position with its shifts, sign-ups, and gaps" do
    sign_up(@admin, shift(begins: august(25)))
    shift(begins: august(28))
    shift(position: @other_position, begins: august(27))

    get scheduling_shift_signups_path(year: YEAR)
    assert_response :success

    # max is 20 a shift, so two shifts are 40 seats and one is 20.
    assert_equal [@dirt.title, "2", "1 of 40", "1", "2%"], index_row(@dirt)
    assert_equal [@other_position.title, "1", "0 of 20", "1", "0%"], index_row(@other_position)
  end

  # The whole point of the page is which shifts still need people, so a shift
  # no one can sign up for would only make the year look emptier than it is.
  test "switched-off shifts are left out of the index" do
    shift(begins: august(25), active: true)
    shift(begins: august(26), active: false)

    get scheduling_shift_signups_path(year: YEAR)
    assert_response :success
    assert_equal [@dirt.title, "1", "0 of 20", "1", "0%"], index_row(@dirt)
  end

  test "a position with nothing but switched-off shifts is not listed at all" do
    shift(position: @dirt, active: true)
    shift(position: @other_position, active: false)

    get scheduling_shift_signups_path(year: YEAR)
    assert_response :success
    assert_not_nil index_row(@dirt)
    assert_nil index_row(@other_position)
  end

  # A part-filled shift is not a full one, so the number always rounds down.
  test "the fill percentage rounds down" do
    slot = shift(max: 3)
    sign_up(create_person("Aaa"), slot)
    sign_up(create_person("Bbb"), slot)

    get scheduling_shift_signups_path(year: YEAR)
    assert_response :success
    # Two of three is 66.6 recurring, and 67% would read as nearly full.
    assert_equal "66%", index_row(@dirt).last
  end

  # A shift taking as many people as turn up has no fraction to be a part of.
  test "a position with no sign-up limit reports no percentage instead of dividing by zero" do
    sign_up(@admin, shift(max: 0))

    get scheduling_shift_signups_path(year: YEAR)
    assert_response :success
    assert_equal [@dirt.title, "1", "1", "—", "No limit"], index_row(@dirt)
  end

  # A position can hold both kinds of shift at once. The sign-ups on the
  # unlimited one still count, while it adds nothing to divide by, so the
  # percentage describes only the shifts that have a limit. Pinned because the
  # figure is not obvious and any change to it should be a deliberate one.
  test "a position mixing limited and unlimited shifts totals both" do
    limited = shift(begins: august(24), max: 4)
    2.times { |index| sign_up(create_person("Limited#{index}"), limited) }
    unlimited = shift(begins: august(25), max: 0)
    3.times { |index| sign_up(create_person("Unlimited#{index}"), unlimited) }

    get scheduling_shift_signups_path(year: YEAR)
    assert_response :success
    # Five people over four seats: everyone counted, the unlimited shift adding
    # none of its own.
    assert_equal [@dirt.title, "2", "5 of 4", "—", "125%"], index_row(@dirt)
  end

  test "only the chosen year is counted" do
    shift(begins: august(25))
    shift(begins: august(25, year: 2019))

    get scheduling_shift_signups_path(year: YEAR)
    assert_response :success
    assert_equal "1", index_row(@dirt)[1]
  end

  test "the index is ordered by position title, case-insensitively" do
    lower = Position.create!(title: "aardvark position", type: "Frontline", active: true)
    upper = Position.create!(title: "Baker position", type: "Frontline", active: true)
    shift(position: upper)
    shift(position: lower)

    get scheduling_shift_signups_path(year: YEAR)
    assert_response :success
    assert_equal ["aardvark position", "Baker position"],
                 index_titles & ["aardvark position", "Baker position"]
  end

  test "a year with no shifts says so" do
    get scheduling_shift_signups_path(year: YEAR)
    assert_response :success
    assert_select "body", text: /No #{YEAR} shifts were found/
    assert_report_card count: 0
  end

  test "a year below the floor falls back to the current year" do
    get scheduling_shift_signups_path(year: 2007)
    assert_response :success
    assert_select "body", text: /#{Current.year} Shift Sign-Ups/
  end

  # --- Narrowing the list -------------------------------------------------

  test "the empty filter keeps only positions with a shift no one has taken" do
    sign_up(@admin, shift(position: @dirt, max: 1))              # full, no gaps
    shift(position: @other_position)                             # no one on it

    get scheduling_shift_signups_path(year: YEAR, show: "empty")
    assert_response :success
    assert_nil index_row(@dirt)
    assert_not_nil index_row(@other_position)
  end

  test "the low filter keeps only positions under the fill threshold" do
    # One of twenty is 5%, well under; nineteen of twenty is 95%.
    sign_up(@admin, shift(position: @dirt))
    thin = shift(position: @other_position, max: 40)
    19.times { |index| sign_up(create_person("Filler#{index}"), thin) }

    get scheduling_shift_signups_path(year: YEAR, show: "low")
    assert_response :success
    assert_not_nil index_row(@dirt), "5% full is under the threshold"
    assert_nil index_row(@other_position), "47% full is over it"
  end

  # A position with no limit cannot be under a percentage it does not have.
  test "the low filter leaves out a position with no sign-up limit" do
    shift(position: @dirt, max: 0)
    shift(position: @other_position)

    get scheduling_shift_signups_path(year: YEAR, show: "low")
    assert_response :success
    assert_nil index_row(@dirt)
    assert_not_nil index_row(@other_position)
  end

  # A stale bookmark would otherwise narrow nothing while drawing a chip that
  # claimed it had, and `?show[]=x` arrives as an Array no lookup matches.
  test "an unrecognised filter shows everything" do
    shift(position: @dirt)

    ["nonsense", ["empty"]].each do |value|
      get scheduling_shift_signups_path(year: YEAR, show: value)
      assert_response :success
      assert_not_nil index_row(@dirt), "#{value.inspect} should fall back to showing everything"
      assert_select "a[aria-label^='Remove filter']", count: 0
    end
  end

  test "an applied filter draws a chip that can be removed" do
    shift(position: @dirt)

    get scheduling_shift_signups_path(year: YEAR, show: "empty")
    assert_response :success
    assert_select "a[aria-label=?]", "Remove filter: Showing: With empty shifts"
  end

  # The selector's GET carries only the year, so without the hidden field a
  # reader changing year would silently lose the filter they had applied.
  test "the year selector keeps the filter" do
    shift(position: @dirt)

    get scheduling_shift_signups_path(year: YEAR, show: "empty")
    assert_response :success
    assert_select "form input[type=hidden][name=show][value=empty]", minimum: 1
  end

  # --- One position's shifts ----------------------------------------------

  test "shifts are listed earliest first" do
    shift(begins: august(28), description: "last")
    shift(begins: august(24), description: "first")
    shift(begins: august(26), description: "middle")

    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_equal %w[first middle last],
                 shift_rows.map { |cells| cells.join(" ")[/first|middle|last/] }
  end

  test "the position page totals shifts, sign-ups, and empty shifts" do
    taken = shift(begins: august(24))
    sign_up(@admin, taken)
    sign_up(@event_manager, taken)
    shift(begins: august(26))

    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR)
    assert_response :success

    assert_equal "2Shifts", stat_box("Shifts")
    assert_equal "2 of 40Signed Up", stat_box("Signed Up")
    assert_equal "1Empty Shifts", stat_box("Empty Shifts")
  end

  # The index and the page it links to must never disagree about a position.
  test "the position page totals match the index row" do
    sign_up(@admin, shift(begins: august(24)))
    shift(begins: august(26))

    get scheduling_shift_signups_path(year: YEAR)
    index_cells = index_row(@dirt)

    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR)
    assert_equal "#{index_cells[1]}Shifts", stat_box("Shifts")
    assert_equal "#{index_cells[2]}Signed Up", stat_box("Signed Up")
    assert_equal "#{index_cells[3]}Empty Shifts", stat_box("Empty Shifts")
  end

  # On a coverage report an empty shift is the finding, so it is named rather
  # than left to the row's colour.
  test "a shift no one has taken is badged, not just tinted" do
    shift(description: "graveyard")

    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_select "td", text: /Empty/
    assert_select "tbody tr[class*='bg-error']", count: 1
  end

  test "a thinly covered shift is tinted amber rather than red" do
    sign_up(@admin, shift(max: 20)) # 5%

    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_select "tbody tr[class*='bg-warning']", count: 1
    assert_select "tbody tr[class*='bg-error']", count: 0
  end

  # A few people against a big limit round down to 0%, but somebody is on the
  # shift. Colouring it red would contradict the "Empty" badge it does not have.
  test "a shift that rounds down to nought is amber, not red" do
    sign_up(@admin, shift(max: 1000))

    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_select "td", text: /0%/
    assert_select "tbody tr[class*='bg-warning']", count: 1
    assert_select "tbody tr[class*='bg-error']", count: 0
    assert_select "td", { text: /Empty/, count: 0 }
  end

  test "a shift with no sign-up limit says so instead of showing a bar" do
    sign_up(@admin, shift(max: 0))

    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_select "td", text: /No limit/
    assert_select "tbody [role=progressbar]", count: 0
  end

  test "switched-off shifts stay off the position page" do
    shift(begins: august(24), active: true, description: "open")
    shift(begins: august(26), active: false, description: "switched off")

    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_equal "1Shifts", stat_box("Shifts")
    assert_select "body", text: /open/
    assert_select "body", { text: /switched off/, count: 0 }
  end

  # A hand-typed URL must not read past the year the rest of the page describes.
  test "another year's shifts stay off the position page" do
    shift(begins: august(25), description: "this year")
    shift(begins: august(25, year: 2019), description: "other year")

    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_equal 1, shift_rows.size
    assert_select "body", text: /this year/
  end

  test "a position with no shifts this year gets an empty state, not a blank table" do
    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_select "body", text: /#{Regexp.escape(@dirt.title)} has no active #{YEAR} shifts/
    assert_report_card count: 0
  end

  test "an unknown position is sent back to the list" do
    get scheduling_shift_signups_position_path(0, year: YEAR)
    assert_redirected_to scheduling_shift_signups_path(year: YEAR)
    assert_equal Scheduling::ShiftSignupsController::POSITION_NOT_FOUND, flash[:error]
  end

  # --- The legend ---------------------------------------------------------

  # The card holds a legend for rows and nothing else, so a page offers it only
  # when it has rows -- the two empty states above expect it gone -- and words
  # it about its own kind of row.
  test "each page explains its row colors about its own kind of row" do
    shift

    get scheduling_shift_signups_path(year: YEAR)
    assert_report_card
    assert_select "details dt", text: "What do the row colors mean?"
    assert_select "details dd", text: /signed up for the position/

    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR)
    assert_report_card
    assert_select "details dd", text: /signed up for the shift/
  end

  # --- Cross-link ---------------------------------------------------------

  # The schedule report names the people behind these counts. It is offered by
  # asking that page, so it cannot go on promising a page that stopped
  # admitting the reader.
  test "the schedule link is offered to readers the schedule report admits" do
    shift

    [@admin, @slot_editor, @event_manager].each do |viewer|
      sign_in_as(viewer)
      get scheduling_shift_signups_position_path(@dirt.id, year: YEAR)
      assert_select "a[href=?]",
                    scheduling_schedule_by_position_position_path(@dirt.id, year: YEAR),
                    { count: 1 }, "#{viewer.callsign} reads the schedule and should be offered it"
    end
  end

  # --- Unique dom ids -----------------------------------------------------

  test "both pages render unique dom ids" do
    sign_up(@admin, shift(begins: august(24)))
    shift(position: @other_position, begins: august(25))

    get scheduling_shift_signups_path(year: YEAR)
    assert_response :success
    assert_unique_dom_ids

    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR)
    assert_response :success
    assert_unique_dom_ids
  end

  # --- CSV ----------------------------------------------------------------

  test "the whole year exports one row per shift" do
    slot = shift(begins: august(25), hours: 6, description: "Playa")
    sign_up(create_person("Zebra"), slot)
    sign_up(create_person("Aardvark"), slot)

    get scheduling_shift_signups_path(year: YEAR, format: :csv)
    assert_response :success

    lines = response.body.split("\n")
    assert_equal "Position,Begins,Ends,Description,Signed Up,Max", lines.first
    # The whole line: a prefix match would pass whether or not the later columns
    # were emitted at all.
    assert_equal [@dirt.title, august(25).iso8601, (august(25) + 6.hours).iso8601,
                  "Playa", 2, 20].join(","),
                 lines[1]
  end

  # The export is named for the year, so holding back most of it because a
  # filter happened to be on would be a spreadsheet no one could trust.
  test "the export ignores the filter the page is showing" do
    sign_up(@admin, shift(position: @dirt, max: 1, description: "full"))
    shift(position: @other_position, description: "empty")

    get scheduling_shift_signups_path(year: YEAR, show: "empty", format: :csv)
    assert_response :success

    lines = response.body.split("\n")
    assert_equal 3, lines.size, "both positions belong in the export"
    assert_match(/full/, response.body)
    assert_match(/empty/, response.body)
  end

  test "a position exports only its own shifts" do
    shift(position: @dirt, description: "mine")
    shift(position: @other_position, description: "theirs")

    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR, format: :csv)
    assert_response :success

    lines = response.body.split("\n")
    assert_equal 2, lines.size
    assert_match(/mine/, lines[1])
  end

  test "the export leaves out switched-off shifts, as the page does" do
    shift(begins: august(24), active: true, description: "open")
    shift(begins: august(26), active: false, description: "switched off")

    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR, format: :csv)
    assert_response :success
    assert_equal 2, response.body.split("\n").size
  end

  # --- Timezones ----------------------------------------------------------

  # The export has to name the same clock time the page does. Shifting a shift
  # into the machine's own zone first moves it by the difference between that
  # zone and the app's, which is an hour on the machines this runs on.
  test "the export names the same clock time the page shows" do
    begins = Time.zone.local(YEAR, 2, 17, 0, 30, 0)
    shift(begins:, hours: 4)

    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR)
    assert_response :success
    page_time = shift_rows.first.first

    get scheduling_shift_signups_position_path(@dirt.id, year: YEAR, format: :csv)
    exported = response.body.split("\n")[1].split(",")[1]

    assert_equal begins.iso8601, exported
    # And the page agrees, digit for digit, rather than only in the same zone.
    assert_match(/00:30/, page_time)
    assert_match(/T00:30/, exported)
  end
end
