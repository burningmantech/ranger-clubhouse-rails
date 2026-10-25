# frozen_string_literal: true

require "test_helper"

class Scheduling::HqForecastControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include DomIdTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2031

  setup do
    Rails.cache.clear
    Current.reset

    # A future YEAR is legal because travel_to makes it the current one --
    # setup_year clamps a requested year to no later than that.
    travel_to Time.zone.local(YEAR, 8, 26, 12, 0, 0)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_SLOTS, "Edit Slots")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")

    @admin = person(:active_ranger)
    @slot_editor = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@slot_editor, Role::EDIT_SLOTS)

    @window = ensure_position(Position::HQ_WINDOW, "HQ Window")
    @dirt = ensure_position(Position::DIRT, "Dirt")
    @burn = ensure_position(Position::BURN_PERIMETER, "Burn Perimeter")

    # HQ open 06:00 - 18:00 with a window worker on all day, and one Dirt shift
    # sending people through it.
    @hq = create_slot(@window, begins: at(6), ends: at(18))
    sign_up(@admin, @hq)
    sign_up(@slot_editor, create_slot(@dirt, begins: at(9), ends: at(13)))

    sign_in_as(@admin)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  def ensure_position(id, title)
    Position.find_or_create_by!(id:) { |position| position.title = title }
  end

  def at(hour, minute = 0, day: 27) = Time.zone.local(YEAR, 8, day, hour, minute, 0)

  def sign_up(person, slot) = PersonSlot.create!(person_id: person.id, slot_id: slot.id)

  def index_path(year: YEAR, **options) = scheduling_hq_forecast_path(year:, **options)

  def burns_path(year: YEAR, **options)
    scheduling_hq_forecast_burn_perimeters_path(year:, **options)
  end

  # --- Authorization ------------------------------------------------------

  test "admin, edit slots, and event management may all view the report" do
    event_manager = @outsider
    grant_role(event_manager, Role::EVENT_MANAGEMENT)

    [@admin, @slot_editor, event_manager].each do |viewer|
      sign_in_as(viewer)
      get index_path
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "timesheet management is not admitted, unlike the shift drop report" do
    grant_role(@outsider, Role::TIMESHEET_MANAGEMENT)
    sign_in_as(@outsider)

    get index_path
    assert_redirected_to me_root_path
  end

  test "someone without any of the roles is turned away" do
    sign_in_as(@outsider)

    get index_path
    assert_redirected_to me_root_path
  end

  # Every page of the report is behind the same gate, the sign-up list
  # included -- it names people, and it is reachable on its own.
  test "the burn page and the signups list are behind the same gate" do
    sign_in_as(@outsider)

    get burns_path
    assert_redirected_to me_root_path

    get scheduling_hq_forecast_people_path(position_id: Position::HQ_WINDOW,
                                           period: at(9).iso8601, interval: 60)
    assert_redirected_to me_root_path

    get scheduling_hq_forecast_shift_path(@hq.id)
    assert_redirected_to me_root_path
  end

  # --- The forecast --------------------------------------------------------

  # The chart is the page; without this it can vanish and every other
  # assertion about its parts still passes on nothing.
  test "each day draws a traffic lane, and a lane only for a desk with a shift that day" do
    get index_path

    assert_response :success
    assert_select ".hq-gantt", count: 1
    # The one window shift: traffic on top, the window beneath, no other desk.
    assert_select ".hq-gantt-lane", count: 2
    assert_select ".hq-gantt", text: /HQ Window/
    assert_select ".hq-gantt", text: /HQ Lead|HQ Short|HQ Runner|Pre-event/, count: 0
  end

  test "a pre-event desk has a lane on the days it has a shift and none on the others" do
    pre_event = ensure_position(Position::HQ_WINDOW_PRE_EVENT, "HQ Window - Pre-event")
    sign_up(@slot_editor, create_slot(pre_event, begins: at(6, day: 26), ends: at(18, day: 26)))

    get index_path

    assert_select "[role=group][aria-label^=\"Tue Aug 26\"] .hq-gantt-lane", count: 2
    assert_select "[role=group][aria-label^=\"Tue Aug 26\"]", text: /HQ Window - Pre-event/
    assert_select "[role=group][aria-label^=\"Wed Aug 27\"] .hq-gantt-lane", count: 2
    assert_select "[role=group][aria-label^=\"Wed Aug 27\"]", text: /Pre-event/, count: 0
  end

  test "each period's traffic bar says its arrivals and departures in words" do
    get index_path

    assert_select "[role=img][aria-label=?]", "09:00: 1 checking in, 0 checking out"
    assert_select "[role=img][aria-label=?]", "13:00: 0 checking in, 1 checking out"
  end

  test "the day is named on its chart" do
    get index_path

    assert_select "[role=group][aria-label=?]", "Wed Aug 27 HQ shifts and check-in/out traffic"
  end

  test "a period with no one answering the window is hatched and says so" do
    # A day of HQ shifts with no one signed up for them at all.
    PersonSlot.where(slot_id: @hq.id).delete_all

    get index_path

    # The whole column is striped, however little traffic there is to draw,
    # and the words say it too -- the stripes alone are not a signal.
    assert_select "[role=img].hq-gantt-gap[aria-label$=?]", "no lead, short, or window on duty",
                  minimum: 1
  end

  test "a staffed period is neither hatched nor flagged" do
    get index_path

    assert_response :success
    # Bars have to exist for their not being hatched to mean anything.
    assert_select ".hq-gantt-fill", minimum: 1
    assert_select ".hq-gantt-lane .hq-gantt-gap", count: 0
    assert_select "[aria-label*=?]", "on duty", count: 0
  end

  # Nothing scheduled at any desk is HQ closed, not HQ short-handed.
  test "the hours HQ is closed are not flagged" do
    sign_up(@admin, create_slot(@window, begins: at(6, day: 28), ends: at(18, day: 28)))

    get index_path

    # Overnight between the two window shifts nothing is scheduled at any desk.
    assert_select "[role=img][aria-label=?]", "20:00: 0 checking in, 0 checking out"
    assert_select ".hq-gantt-lane .hq-gantt-gap", count: 0
  end

  test "a shift running past midnight is drawn on both days it touches" do
    night = create_slot(@window, begins: at(22), ends: at(2, day: 28))
    sign_up(@admin, night)

    get index_path

    path = scheduling_hq_forecast_shift_path(night.id)
    # Each end says which day it falls on, and the bar is squared off where
    # the day cuts it.
    assert_select "a[href=?][aria-label=?] .rounded-e-none", path,
                  "1/20 signed up, HQ Window, 22:00 to Thu @ 02:00"
    assert_select "a[href=?][aria-label=?] .rounded-s-none", path,
                  "1/20 signed up, HQ Window, Wed @ 22:00 to 02:00"
  end

  # A shift with its end typed a week out: the weekday alone would read as
  # this week's, and the shift as a twelve-hour one.
  test "a shift ending days later names the date it ends on" do
    long = create_slot(@window, begins: at(6), ends: at(18, day: 27) + 7.days)
    sign_up(@admin, long)

    get scheduling_hq_forecast_shift_path(long.id)

    assert_select "turbo-frame#modal", text: /HQ Window — Wed Aug 27 @ 06:00 to Wed Sep 3 @ 18:00/
  end

  test "overlapping shifts at one desk get a lane each" do
    sign_up(@slot_editor, create_slot(@window, begins: at(10), ends: at(14)))

    get index_path

    # Traffic, then the window twice.
    assert_select ".hq-gantt-lane", count: 3
  end

  # --- The period width ----------------------------------------------------

  test "a narrower period draws more traffic bars" do
    get index_path
    hourly = css_select(".hq-gantt-fill").size

    get index_path(interval: 15)

    assert_operator css_select(".hq-gantt-fill").size, :>, hourly
  end

  test "a period width the report does not offer falls back to the default" do
    get index_path(interval: 7)

    assert_response :success
    # The select shows what was actually used, not what was asked for.
    assert_select "select[name=interval] option[selected][value=?]", "60"
  end

  test "a period width that is not a number at all is refused the same way" do
    get index_path(interval: { evil: "hash" })

    assert_response :success
    assert_select "select[name=interval] option[selected][value=?]", "60"
  end

  # --- Filters -------------------------------------------------------------

  test "a day filter narrows the page to that day" do
    create_slot(@window, begins: at(6, day: 28), ends: at(18, day: 28))

    get index_path
    assert_select ".hq-gantt", count: 2

    get index_path(day: "0828")
    assert_select ".hq-gantt", count: 1
    assert_select "[role=group][aria-label^=?]", "Thu Aug 28"
    assert_select "*", text: "Showing 1 of 2 days"
  end

  test "a filter the page does not offer shows everything rather than nothing" do
    create_slot(@window, begins: at(6, day: 28), ends: at(18, day: 28))

    get index_path(day: "nonsense")

    assert_response :success
    assert_select ".hq-gantt", count: 2
    # Nothing was narrowed, so nothing should claim to have been.
    assert_select "a[aria-label^=?]", "Remove filter", count: 0
  end

  # A GET form replaces the whole query string, so the year has to ride along
  # inside it or Apply would bounce the reader back to the current year.
  test "the filter form carries the year" do
    get index_path

    assert_select "input[type=hidden][name=year][value=?]", YEAR.to_s
  end

  # --- The spreadsheet -----------------------------------------------------

  test "the export holds every period even while the page is filtered" do
    # A second day, so filtering to one of them really does hold something back.
    create_slot(@window, begins: at(6, day: 28), ends: at(18, day: 28))

    get index_path(format: :csv)
    whole_year = response.body.split("\n").size

    get index_path(format: :csv, day: "0827")

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/attachment; filename="#{YEAR}-hq-forecast\.csv"/, response.headers["Content-Disposition"])

    rows = response.body.split("\n")
    assert_equal "Time (1 hour interval),Check In,Check Out,HQ Lead - Pre-event,HQ Window - Pre-event," \
                 "HQ Lead,HQ Short,HQ Window,HQ Runner",
                 rows.first
    # The filters narrow the page, never the file.
    assert_equal whole_year, rows.size
    assert_operator rows.size, :>, 25
  end

  # --- Who is signed up ----------------------------------------------------

  # A shift's bar has to be the thing that opens its list, and it has to open
  # it in the dialog rather than walking away from the report.
  test "a shift's bar opens the dialog of who is signed up for it" do
    get index_path

    assert_response :success
    assert_select "a[href=?][data-turbo-frame=modal][aria-label=?]",
                  scheduling_hq_forecast_shift_path(@hq.id),
                  "1/20 signed up, HQ Window, 06:00 to 18:00", text: "1/20"
  end

  # Nought opens nothing -- there is no one behind it to show.
  test "a shift no one has signed up for opens nothing, and is hatched" do
    PersonSlot.where(slot_id: @hq.id).delete_all

    get index_path

    assert_select "a[href=?]", scheduling_hq_forecast_shift_path(@hq.id), count: 0
    assert_select "[role=img][aria-label=?] .hq-gantt-vacant",
                  "0/20 signed up, HQ Window, 06:00 to 18:00"
  end

  # The list has to agree with the count on the bar that opened it.
  test "a shift's dialog lists its own people and no one else's" do
    sign_up(@slot_editor, create_slot(@window, begins: at(10), ends: at(14)))

    get scheduling_hq_forecast_shift_path(@hq.id)

    assert_response :success
    assert_select "turbo-frame#modal", text: /HQ Window — Wed Aug 27 @ 06:00 to 18:00/
    assert_select "td", text: /#{Regexp.escape(@admin.callsign)}/
    assert_select "td", text: /#{Regexp.escape(@slot_editor.callsign)}/, count: 0
    # Everyone on one shift starts together; the title already says when.
    assert_select "th", text: "Shift Start", count: 0
  end

  # The list is read to size up a roster, so each row says whether the person
  # is on site and which HQ desks they have put years in at.
  test "the dialog says who is on site and their years at each HQ desk" do
    ensure_position(Position::HQ_RUNNER, "HQ Runner")
    ensure_position(Position::HQ_LEAD, "HQ Lead")
    @admin.update_columns(on_site: true)
    entry = ->(position_id, year, off_duty: Time.zone.local(year, 8, 28, 16)) do
      Timesheet.create!(person_id: @admin.id, position_id:, additional_notes: "test",
                        on_duty: Time.zone.local(year, 8, 28, 10), off_duty:)
    end
    [2027, 2028, 2029, 2029, 2030].each { |year| entry.call(Position::HQ_WINDOW, year) }
    entry.call(Position::HQ_RUNNER, 2026)
    # An open entry is not a year put in yet.
    entry.call(Position::HQ_LEAD, 2030, off_duty: nil)
    sign_up(@slot_editor, @hq)

    get scheduling_hq_forecast_shift_path(@hq.id)

    assert_response :success
    assert_select "th", text: "On Site"
    assert_select "th", text: "HQ Years"
    assert_select "tr", text: /#{Regexp.escape(@admin.callsign)}.*On Site/m do
      # Alphabetical: Runner before Window, whatever order the desks are drawn in.
      assert_select "li:first-child", text: "HQ Runner (1 year): 2026"
      assert_select "li:last-child", text: "HQ Window (4 years): 2027 - 2030"
      assert_select "li", text: /HQ Lead/, count: 0
    end
    assert_select "tr", text: /#{Regexp.escape(@slot_editor.callsign)}.*Off Site/m do
      assert_select "td", text: "No years at an HQ desk"
    end
  end

  # Opened only for one of HQ's own shifts. Any other would turn the dialog
  # into a roster lookup for the whole event.
  test "the shift dialog refuses a shift that is not at an HQ desk" do
    get scheduling_hq_forecast_shift_path(create_slot(@dirt, begins: at(9)).id)

    assert_response :not_found
  end

  test "the shift dialog refuses a shift that is not a number at all" do
    get scheduling_hq_forecast_shift_path("nonsense")

    assert_response :not_found
  end

  # Read in base ten, as the digits say: "0x1A" is not slot 26, and a leading
  # nought is not octal.
  test "the shift dialog reads its id in base ten" do
    get scheduling_hq_forecast_shift_path("0#{@hq.id}")
    assert_response :success

    get scheduling_hq_forecast_shift_path("0x#{@hq.id.to_s(16)}")
    assert_response :not_found
  end

  test "the shift dialog says so when no one is signed up" do
    PersonSlot.where(slot_id: @hq.id).delete_all

    get scheduling_hq_forecast_shift_path(@hq.id)

    assert_select "turbo-frame#modal", text: /No one is signed up for this shift/
  end

  # The burn page keeps its table, and the count there opens the same dialog.
  test "a burn page staffing count is a link into the dialog for its own period" do
    sign_up(@slot_editor, create_slot(@burn, begins: at(9), ends: at(11), description: "Man"))

    get burns_path

    assert_response :success
    expected = scheduling_hq_forecast_people_path(position_id: Position::HQ_WINDOW,
                                                  period: at(9).iso8601, interval: 60)
    assert_select "a[href=?][data-turbo-frame=modal]", expected
  end

  test "a burn table has a column only for the desks with a shift in its periods" do
    sign_up(@slot_editor, create_slot(@burn, begins: at(9), ends: at(11), description: "Man"))

    get burns_path

    assert_select "th", text: "HQ Window"
    assert_select "th", text: /HQ Lead|HQ Short|HQ Runner|Pre-event/, count: 0
  end

  # The period table is drawn only here now, so its warnings are tested here.
  test "a burn period with no one answering the window is flagged, and its nought opens nothing" do
    # The window shift is still scheduled, so HQ is open -- with no one on it.
    PersonSlot.where(slot_id: @hq.id).delete_all
    sign_up(@slot_editor, create_slot(@burn, begins: at(9), ends: at(11), description: "Man"))

    get burns_path

    assert_select "tr.\\!bg-warning\\/10 i.fa-triangle-exclamation", minimum: 1
    assert_select "tr.\\!bg-warning\\/10 .sr-only", text: "no lead, short, or window on duty"
    assert_select "td span.text-stone-subtle", text: "0", minimum: 1
    empty = scheduling_hq_forecast_people_path(position_id: Position::HQ_WINDOW,
                                               period: at(9).iso8601, interval: 60)
    assert_select "a[href=?]", empty, count: 0
  end

  test "a staffing count opens the list of who it stands for" do
    get scheduling_hq_forecast_people_path(position_id: Position::HQ_WINDOW,
                                           period: at(9).iso8601, interval: 60)

    assert_response :success
    assert_select "turbo-frame#modal"
    assert_select "td", text: /#{Regexp.escape(@admin.callsign)}/
  end

  # The list is only ever opened for one of HQ's own desks. Any other position
  # would turn the dialog into a roster lookup for the whole event.
  test "the signups list refuses a position that is not an HQ desk" do
    get scheduling_hq_forecast_people_path(position_id: Position::DIRT,
                                           period: at(9).iso8601, interval: 60)

    assert_response :not_found
  end

  # A nested parameter has no number to ask for; it should be turned away, not
  # raise on the way to being turned away.
  test "the signups list refuses a position that is not a number at all" do
    get scheduling_hq_forecast_people_path(position_id: { evil: "hash" },
                                           period: at(9).iso8601, interval: 60)

    assert_response :not_found
  end

  test "the signups list refuses a period it cannot read" do
    get scheduling_hq_forecast_people_path(position_id: Position::HQ_WINDOW,
                                           period: "not-a-time", interval: 60)

    assert_response :not_found
  end

  test "the signups list says so when no one is on" do
    get scheduling_hq_forecast_people_path(position_id: Position::HQ_RUNNER,
                                           period: at(9).iso8601, interval: 60)

    assert_response :success
    assert_select "turbo-frame#modal", text: /No one is signed up/
  end

  # --- The burn page -------------------------------------------------------

  test "the burn page lists one section per burn" do
    sign_up(@slot_editor, create_slot(@burn, begins: at(20), ends: at(22), description: "Man Burn"))

    get burns_path

    assert_response :success
    assert_select "caption", text: /Man Burn/
  end

  # The rows carry only the hour, so two unnamed burns on different nights
  # would otherwise be two sections with the same heading.
  test "a burn with nothing written on it is still told apart by its night" do
    create_slot(@burn, begins: at(20), ends: at(22), description: nil)
    create_slot(@burn, begins: at(20, day: 28), ends: at(22, day: 28), description: nil)

    get burns_path

    assert_response :success
    assert_select "caption", text: /Burn Perimeter — Wed Aug 27/
    assert_select "caption", text: /Burn Perimeter — Thu Aug 28/
  end

  test "the burn page says so when no burns are scheduled" do
    get burns_path

    assert_response :success
    assert_select "*", text: /No #{YEAR} burn perimeter shifts have been scheduled/
  end

  test "both pages link to each other and keep the period width" do
    get index_path(interval: 15)

    assert_select "a[href=?]",
                  scheduling_hq_forecast_burn_perimeters_path(year: YEAR, interval: 15)

    get burns_path(interval: 15)

    assert_select "a[href=?]", scheduling_hq_forecast_path(year: YEAR, interval: 15)
  end

  # --- Empty and unique ----------------------------------------------------

  test "a year with no HQ shifts says so" do
    get index_path(year: YEAR - 1)

    assert_response :success
    assert_select "*", text: /No #{YEAR - 1} HQ shifts have been scheduled/
  end

  test "the page draws no duplicate DOM ids" do
    create_slot(@window, begins: at(6, day: 28), ends: at(18, day: 28))

    get index_path
    assert_unique_dom_ids
  end

  # Two burns half an hour apart are separate sections whose periods fall in
  # the same hour, so nothing either section names may collide.
  test "the burn page draws no duplicate DOM ids when two burns share an hour" do
    sign_up(@slot_editor, create_slot(@burn, begins: at(20), ends: at(22), description: "Man"))
    sign_up(@admin, create_slot(@burn, begins: at(20, 30), ends: at(22, 30), description: "Temple"))

    get burns_path

    assert_response :success
    # Both burns really are on the page; without this the check below passes on
    # a page holding one section, or none.
    assert_select "caption", count: 2
    assert_unique_dom_ids
  end
end
