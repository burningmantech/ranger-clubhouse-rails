# frozen_string_literal: true

require "test_helper"

class Scheduling::ShiftCoverageControllerTest < ActionDispatch::IntegrationTest
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

    # The Command report's rows come from the Dirt shifts; its columns are the
    # posts covering them.
    @dirt = ensure_position(Position::DIRT, "Dirt")
    @ood = ensure_position(Position::OOD, "OOD")
    @troubleshooter = ensure_position(Position::TROUBLESHOOTER, "Troubleshooter")
    @ts_mentee = ensure_position(Position::TROUBLESHOOTER_MENTEE, "Troubleshooter Mentee")
    @intercept = ensure_position(Position::INTERCEPT, "Intercept")

    # Ragged on purpose: the row it draws has to be the rounded 06:00 - 18:00.
    @period = create_slot(@dirt, begins: day_at(6, 15), ends: day_at(18, 20))

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

  def day_at(hour, minute = 0, day: 27)
    Time.zone.local(YEAR, 8, day, hour, minute, 0)
  end

  def sign_up(person, slot)
    PersonSlot.create!(person_id: person.id, slot_id: slot.id)
  end

  def index_path(year: YEAR, **options) = scheduling_shift_coverage_path(year:, **options)

  # response.body is not a witness for a callsign: the navbar greets the
  # signed-in user by callsign on every page, so a body-wide check passes
  # whether or not the cell rendered.
  #
  # The post is named too. Without it the assertion passes on any of the
  # eighteen columns, so a report that put everybody in the wrong one -- or in
  # every one -- would still be green. The mobile data-label carries the
  # column, which is how the cell can be picked out.
  def assert_covered(person, post)
    assert_select "td[data-label=?]", post, text: /#{Regexp.escape(person.callsign)}/, minimum: 1
  end

  def assert_not_covered(person, post)
    assert_select "td[data-label=?]", post, text: /#{Regexp.escape(person.callsign)}/, count: 0
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

  # The shift drop report next door admits Timesheet Management; this one hangs
  # off the slot policy, which never has.
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

  # --- Periods ------------------------------------------------------------

  test "a shift with ragged times draws a row rounded to the nearest hour" do
    get index_path

    assert_response :success
    assert_select "th[scope=row]", text: /06:00 – 18:00/
    # The table's own caption, not the page: every day is named in the day
    # filter's options too, so a body-wide check passes on those instead.
    assert_select "caption", text: /Wed Aug 27/
  end

  # Two base shifts running the same hours hold the same answer, so the report
  # would otherwise print the identical row twice.
  test "base shifts covering the same hours draw one row" do
    create_slot(@dirt, begins: day_at(6, 5), ends: day_at(18, 10))

    get index_path

    assert_response :success
    assert_select "th[scope=row]", text: /06:00 – 18:00/, count: 1
  end

  # --- Cells --------------------------------------------------------------

  test "someone on an overlapping shift appears under their post" do
    sign_up(@outsider, create_slot(@ood, begins: day_at(8), ends: day_at(16)))

    get index_path

    assert_response :success
    assert_covered(@outsider, "OOD")
    assert_not_covered(@outsider, "RSL")
  end

  # A shift covering part of the row is not the same answer as one covering all
  # of it, and a bare callsign reads as the second.
  test "a shift covering only part of the row prints its hours" do
    sign_up(@outsider, create_slot(@ood, begins: day_at(8), ends: day_at(16)))
    # Exactly the row's own hours once rounded, so its hours add nothing.
    sign_up(@admin, create_slot(@troubleshooter, begins: day_at(6, 10), ends: day_at(18, 5)))

    get index_path

    assert_response :success
    assert_select "td[data-label=OOD]", text: /08:00 – 16:00/
    assert_select "td[data-label=TS]", text: /#{Regexp.escape(@admin.callsign)}/
    assert_select "td[data-label=TS]", { text: /–.*:/, count: 0 },
                  "a shift filling the row says nothing about its hours"
  end

  # One column can cover a position and its junior version. Two of them
  # starting together but ending apart are two answers, not one.
  test "people who start together but finish apart are not merged" do
    sign_up(@admin, create_slot(@troubleshooter, begins: day_at(8), ends: day_at(16)))
    sign_up(@outsider, create_slot(@ts_mentee, begins: day_at(8), ends: day_at(10)))

    get index_path

    assert_response :success
    assert_select "td[data-label=TS]", text: /08:00 – 16:00/
    assert_select "td[data-label=TS]", text: /08:00 – 10:00/
  end

  # A shift that ends exactly where the row starts hands over at the boundary
  # rather than covering any of it.
  test "shifts that only touch the row's edges are left out" do
    sign_up(@outsider, create_slot(@ood, begins: day_at(0), ends: day_at(6)))
    sign_up(@slot_editor, create_slot(@ood, begins: day_at(18), ends: day_at(23)))

    get index_path

    assert_response :success
    assert_not_covered(@outsider, "OOD")
    assert_not_covered(@slot_editor, "OOD")
  end

  # A row shorter than the rounding collapses onto a single instant. Everyone
  # on duty across it still belongs to it -- the alternative is a row that
  # reads as wholly uncovered while the whole command staff is out.
  test "a row too short to round still collects the people covering it" do
    brief = create_slot(@dirt, begins: day_at(6, 35, day: 29), ends: day_at(7, 25, day: 29))
    sign_up(@outsider, create_slot(@ood, begins: day_at(7, day: 29), ends: day_at(15, day: 29)))

    get index_path(day: "0829")

    assert_response :success
    assert_select "th[scope=row]", text: /07:00 – 07:00/
    assert_covered(@outsider, "OOD")
    assert_not_nil brief
  end

  # One column reads a position and its junior version together, and says which
  # is which.
  test "a junior position is labelled beside the callsign" do
    sign_up(@admin, create_slot(@troubleshooter, begins: day_at(8), ends: day_at(16)))
    sign_up(@outsider, create_slot(@ts_mentee, begins: day_at(8), ends: day_at(16)))

    get index_path

    assert_response :success
    assert_select "td[data-label=TS]", text: /#{Regexp.escape(@outsider.callsign)}\s*\(Mentee\)/
    assert_select "td[data-label=TS]", { text: /#{Regexp.escape(@admin.callsign)}\s*\(/, count: 0 },
                  "a position with no label of its own gets none"
  end

  # The headcount columns count the sign-ups actually on the board rather than
  # a stored total that can drift away from them.
  test "a headcount column counts the people signed up" do
    sign_up(@admin, @period)
    sign_up(@outsider, @period)

    get index_path

    assert_response :success
    assert_select "td[data-label=Dirt]", text: "2"
  end

  test "a post no one is covering shows a dash and is named as vacant" do
    # Somebody on OOD, so the vacant line has to leave a post OUT. With no one
    # signed up at all every post is vacant and the assertion proves nothing.
    sign_up(@outsider, create_slot(@ood, begins: day_at(6), ends: day_at(18)))

    get index_path

    assert_response :success
    # The app-wide "nothing here" placeholder, asked of the helper that renders
    # it rather than spelled as a look-alike dash.
    assert_select "td[data-label=DOOD]", text: ApplicationController.helpers.value_or_dash(nil)
    assert_select "*", text: /Vacant:.*DOOD/
    assert_select "*", { text: /Vacant:[^<]*\bOOD\b/, count: 0 },
                  "a post somebody is covering is not called vacant"
    # A headcount is never vacant -- it prints its number, and zero says the
    # same thing out loud.
    assert_select "*", { text: /Vacant:[^<]*Dirt/, count: 0 }
    assert_select "td[data-label=Dirt]", text: "0"
  end

  # The two Intercept columns answer different questions: who is out there,
  # and how many. Listing both as a headcount named no one.
  test "the intercept report names its interceptors as well as counting them" do
    sign_up(@outsider, create_slot(@intercept, begins: day_at(6), ends: day_at(18)))

    get index_path(type: "intercept")

    assert_response :success
    assert_covered(@outsider, "Interceptors")
    assert_select "td[data-label=Count]", text: "1"
  end

  # --- Filters ------------------------------------------------------------

  test "the shift type can be changed and an unknown one falls back to command" do
    get index_path

    assert_response :success
    assert_select "option[selected][value=?]", "command"

    get index_path(type: "hq")

    assert_response :success
    assert_select "option[selected][value=?]", "hq"
    # The heading, not the page: every type's name is one of the select's own
    # options, so a body-wide check passes whatever type rendered.
    assert_select "strong", text: "HQ Window"

    get index_path(type: "bogus")

    assert_response :success
    assert_select "option[selected][value=?]", "command"
  end

  test "the day filter narrows the report to one day and draws a chip" do
    later = create_slot(@dirt, begins: day_at(6, day: 28), ends: day_at(18, day: 28))
    sign_up(@outsider, create_slot(@ood, begins: later.begins, ends: later.ends))

    get index_path

    assert_response :success
    assert_select "caption", text: /Wed Aug 27/
    assert_select "caption", text: /Thu Aug 28/

    get index_path(day: "0828")

    assert_response :success
    assert_select "caption", { text: /Wed Aug 27/, count: 0 }
    assert_select "caption", text: /Thu Aug 28/
    assert_select "a[href=?]", index_path(type: "command"), text: /Day: Thu Aug 28/
  end

  # A day that is not in this report narrows to nothing while still claiming to
  # have filtered, so it falls back to showing the whole report.
  test "a day the report does not hold falls back to every day" do
    get index_path(day: "0101")

    assert_response :success
    # The caption, for the reason above: the day select lists every day
    # whatever the filter is set to.
    assert_select "caption", text: /Wed Aug 27/
    assert_select "a", { text: /Day:/, count: 0 }
  end

  # The selector posts an action-less GET, so it has to keep the rest of the
  # question with it.
  test "the year selector keeps the shift type and the day" do
    get index_path(type: "hq", day: "0827")

    assert_response :success
    assert_select "select#year-selector-compact option[selected][value=?]", YEAR.to_s
    # hero_panel renders the selector twice (compact and full), so both copies
    # carry the hidden fields and an unscoped assertion would pass on one alone.
    assert_select "form[data-controller=form] input[name=type][value=hq]", count: 2
  end

  # "all" is the filter bar's no-filter value, dropped from every filter a link is
  # built from. The shift type is not a filter, so one slugged "all" keeps its
  # place in the year selector, the export link and the menu.
  test "a shift type slugged all keeps its place in the links the page builds" do
    shift_coverage_group(:command).update_columns(slug: "all")

    get index_path(type: "all")

    assert_response :success
    assert_select "option[selected][value=?]", "all"
    assert_select "form[data-controller=form] input[name=type][value=all]", count: 2
    assert_select "a[href=?]", index_path(type: "all", format: :csv)
  end

  test "the filter form keeps the year" do
    get index_path

    assert_response :success
    assert_select "form input[name=year][value=?]", YEAR.to_s
  end

  # The filter form carries the year alongside the year selector's own field,
  # and every day draws its own table -- both are ways this page could repeat
  # an id, which Turbo's morph reconciles by.
  test "the page carries no duplicate DOM ids" do
    create_slot(@dirt, begins: day_at(6, day: 28), ends: day_at(18, day: 28))

    get index_path(day: "0827")

    assert_response :success
    assert_unique_dom_ids
  end

  # --- Definitions --------------------------------------------------------
  # The shift types and their posts are database rows, so the page and the
  # export read whatever they say today.

  test "a post renamed in the database is its column's heading, on the page and in the export" do
    shift_coverage_position(:command_ood).update!(title: "Officer")
    sign_up(@outsider, create_slot(@ood, begins: day_at(8), ends: day_at(16)))

    get index_path

    assert_response :success
    assert_covered(@outsider, "Officer")
    assert_select "td[data-label=OOD]", count: 0

    get index_path(format: :csv)

    assert_includes response.body.lines.first, ",Officer,DOOD,"
  end

  test "with no shift type called command, the report opens on the first one in the menu" do
    shift_coverage_group(:command).destroy!

    [nil, "bogus"].each do |asked|
      get index_path(type: asked)

      assert_response :success
      assert_select "option[selected][value=?]", "echelon"
      assert_select "strong", text: "Echelon"
    end
  end

  # Renaming is deleting as far as the default goes: the sidebar link carries
  # no ?type=, so it opens whatever the report falls back to.
  test "a shift type renamed away from command takes the default with it" do
    # Past the validations: this is about what the report falls back to, not
    # about whether the positions the fixture names exist in this database.
    shift_coverage_group(:command).update_columns(slug: "dirt")

    get index_path

    assert_response :success
    assert_select "option[selected][value=?]", "dirt"
  end

  test "with no shift types set up the page says so and the export holds only its header" do
    ShiftCoveragePosition.delete_all
    ShiftCoverageGroup.delete_all

    get index_path

    assert_response :success
    assert_select "section[aria-labelledby=scheduling-shift-coverage-header]",
                  text: /once a shift type has been set up/
    assert_select "*", text: /No shift types have been set up for this report yet/

    get index_path(format: :csv)

    assert_response :success
    assert_equal ["Period Start,Period End"], response.body.lines.map(&:strip)
  end

  test "a shift type with no posts yet says so instead of drawing a grid with no columns" do
    ShiftCoveragePosition.where(shift_coverage_group: shift_coverage_group(:command)).delete_all

    get index_path

    assert_response :success
    assert_select "table", count: 0
    assert_select "*", text: /#{shift_coverage_group(:command).title} has no posts set up yet\./
  end

  # ?type[]=hq and ?type[a]=b are not a slug, so they are not looked up as one.
  test "a shift type sent as a list or a hash falls back to command" do
    [["hq"], { a: "b" }].each do |type|
      get index_path(type:)

      assert_response :success
      assert_select "option[selected][value=?]", "command"
    end
  end

  # --- Empty states -------------------------------------------------------

  test "no shifts at all reads differently from no shifts on the day chosen" do
    get index_path(year: YEAR - 2)

    assert_response :success
    assert_select "*", text: /No #{YEAR - 2} Command shifts have been scheduled/

    get index_path(type: "echelon")

    assert_response :success
    assert_select "*", text: /No #{YEAR} Echelon shifts have been scheduled/
  end

  # --- Link gating --------------------------------------------------------

  test "callsigns link only for readers who can open person pages" do
    sign_up(@outsider, create_slot(@ood, begins: day_at(8), ends: day_at(16)))
    sign_in_as(@slot_editor)

    get index_path

    assert_response :success
    # Edit Slots may read this report but not /person/:id -- an unguarded
    # callsign_link would hand them links that bounce to /me.
    assert_select "a", { text: @outsider.callsign, count: 0 }
    assert_covered(@outsider, "OOD")

    # The positive twin: without it, wrapping the callsign in anything at all
    # would turn the guard above green forever while every reader lost the link.
    sign_in_as(@admin)
    get index_path

    assert_response :success
    assert_select "td[data-label=OOD] a", text: @outsider.callsign, count: 1
  end

  # --- Export -------------------------------------------------------------

  test "the export names every column and carries the people" do
    sign_up(@outsider, create_slot(@ood, begins: day_at(8), ends: day_at(16)))
    sign_up(@admin, @period)

    get index_path(format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    lines = response.body.lines
    assert_equal ["Period Start", "Period End", "OOD", "DOOD", "RSL", "RSCI", "RSCIM", "WESL",
                  "Opr", "TS", "LEAL", "GDL", "Tow", "Sanc", "GerPatLd", "GerPat", "Dirt",
                  "GD", "RNR", "Burn"],
                 lines.first.strip.split(",")
    assert_includes response.body, @outsider.callsign
    assert_includes response.body, "#{YEAR}-08-27 06:00"
  end

  # A cell holding several entries carries newlines, which have to survive the
  # trip into a spreadsheet rather than splitting the row.
  test "a cell holding several entries is quoted rather than breaking the row" do
    sign_up(@admin, create_slot(@ood, begins: day_at(6), ends: day_at(12)))
    sign_up(@outsider, create_slot(@ood, begins: day_at(12), ends: day_at(18)))

    get index_path(format: :csv)

    assert_response :success
    assert_equal 1, response.body.lines.count { |line| line.start_with?("#{YEAR}-08-27") },
                 "the one period stays one CSV record"
    assert_operator response.body.lines.size, :>, 2,
                    "the cell's own newlines are inside that record"
    assert_includes response.body, %("06:00 – 12:00\n#{@admin.callsign}\n12:00 – 18:00\n#{@outsider.callsign}")
  end

  # The day filter is a way of reading the page, not a different report.
  test "the export holds every day whatever the page is filtered to" do
    create_slot(@dirt, begins: day_at(6, day: 28), ends: day_at(18, day: 28))

    get index_path(day: "0827", format: :csv)

    assert_response :success
    assert_equal 3, response.body.lines.size, "the header plus both days"
  end

  # A trailing options hash is taken as the route's own options, which drops
  # the params hash and hands the reader the current year's default report.
  test "the export link on the page carries the year and the shift type" do
    get index_path(day: "0827")

    assert_response :success
    # The day is left off on purpose -- the export is always the whole year --
    # but the year and the type have to survive.
    assert_select "a[href=?]", index_path(type: "command", format: :csv)
  end

  test "the export filename carries the year and the shift type" do
    get index_path(type: "hq", format: :csv)

    assert_equal %(attachment; filename="#{YEAR}-shift-coverage-hq.csv"; ) +
                 %(filename*=UTF-8''#{YEAR}-shift-coverage-hq.csv),
                 response.headers["Content-Disposition"]
  end
end
