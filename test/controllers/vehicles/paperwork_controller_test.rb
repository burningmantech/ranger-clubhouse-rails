# frozen_string_literal: true

require "test_helper"

class Vehicles::PaperworkControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ReportCardTestHelper     # card_answer
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    PersonEvent.delete_all
    PersonSlot.delete_all
    Slot.delete_all
    Team.update_all(mvr_eligible: false, pvr_eligible: false)
    Position.update_all(mvr_eligible: false, pvr_eligible: false, mvr_signup_eligible: false)

    @event_manager = person(:echelon_ranger)
    @vehicle_editor = person(:active_ranger)
    @unauthorized = person(:ranger_with_custom_gender)

    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::VEHICLE_INFO_UPDATE, "Vehicle Info Update")
    ensure_role(Role::TRAINER, "Trainer")

    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
    grant_role(@vehicle_editor, Role::VEHICLE_INFO_UPDATE)
    grant_role(@unauthorized, Role::TRAINER)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- gates ----

  test "an anonymous visitor is sent to the login page" do
    get vehicles_paperwork_path

    assert_redirected_to root_path
  end

  test "a user with no relevant role cannot reach the report" do
    sign_in_as(@unauthorized)

    get vehicles_paperwork_path

    assert_redirected_to me_root_path
  end

  # The namespace sidebar renders Menus::VEHICLES, whose Registry item carries a
  # narrower gate than the menu itself -- a Vehicle Info Update holder reaching
  # Paperwork must not be offered a link that would just bounce them to /me.
  test "the vehicles sidebar shows only the items the reader may reach" do
    sign_in_as(@event_manager)
    get vehicles_paperwork_path
    assert_select "#sidebar-drawer-content a[href^='/vehicles/registry']"

    sign_in_as(@vehicle_editor)
    get vehicles_paperwork_path
    assert_select "#sidebar-drawer-content a[href^='/vehicles/paperwork']"
    assert_select "#sidebar-drawer-content a[href^='/vehicles/registry']", count: 0
  end

  test "event management may read the report" do
    sign_in_as(@event_manager)

    get vehicles_paperwork_path

    assert_response :success
  end

  test "a vehicle info update holder may read the report" do
    sign_in_as(@vehicle_editor)

    get vehicles_paperwork_path

    assert_response :success
  end

  test "a vehicle info update holder is given a link to the page they can open" do
    sign_in_as(@vehicle_editor)

    get me_menu_path

    assert_response :success
    # Without the role on the Vehicles category this page is reachable only by
    # typing the URL -- the category, and every link in it, is dropped whole.
    assert_select "a[href*='/vehicles/paperwork']"
    # ...but the registry's own gate is Event Management only, so linking it
    # here would just bounce them to /me.
    assert_select "a[href*='/vehicles/registry']", false
  end

  test "event management still sees both vehicle links" do
    sign_in_as(@event_manager)

    get me_menu_path

    assert_response :success
    assert_select "a[href*='/vehicles/paperwork']"
    assert_select "a[href*='/vehicles/registry']"
  end

  # ----------------------------------------------------------------- page ----

  test "the roster lists an eligible ranger with the reason they are listed" do
    teams(:khaki_team).update!(mvr_eligible: true)
    sign_in_as(@event_manager)

    get vehicles_paperwork_path

    assert_response :success
    assert_select "a", text: @vehicle_editor.callsign
    assert_select "td", text: /Khaki Delegation/
  end

  test "the table renders every column with a matching cell on each row" do
    teams(:khaki_team).update!(mvr_eligible: true, pvr_eligible: true)
    sign_in_as(@event_manager)

    get vehicles_paperwork_path

    assert_response :success
    # Positional selectors are not usable here: every summary row is followed by
    # its detail row, so tr:nth-child(2) is a detail row, not the second person.
    assert_select "thead th", 8
    assert_select "tbody tr:not(.table-detail-row):first-child > *", 8

    # The three "via" columns moved into the detail row. If a heading for one
    # comes back, it is a column again and the collapse has been undone.
    ["Record eligible via", "Eligible sign-ups", "Personal vehicle eligible via"].each do |heading|
      assert_select "thead th", { text: heading, count: 0 }, "#{heading} is a column again"
    end
    assert_select "thead th", text: "Why Eligible"
  end

  test "every summary row has a detail row the toggle beside it actually points at" do
    teams(:khaki_team).update!(mvr_eligible: true, pvr_eligible: true)
    sign_in_as(@event_manager)

    get vehicles_paperwork_path

    assert_response :success
    # A toggle whose aria-controls names nothing is a control that does nothing,
    # and nothing about the rendered page would look wrong.
    # Scoped to the table: the filter panel's own disclosure button is driven by
    # the same controller and would be swept up by a bare attribute selector.
    toggles = css_select("tbody button[data-toggle-dom-id-value]")
    assert_predicate toggles, :any?, "no detail toggles rendered"

    toggles.each do |toggle|
      id = toggle["data-toggle-dom-id-value"]
      assert_equal id, toggle["aria-controls"], "toggle points at #{id} but announces #{toggle["aria-controls"]}"
      assert_select "tr##{id}.table-detail-row", 1, "no detail row for #{id}"
    end
  end

  test "every detail row starts closed" do
    teams(:khaki_team).update!(mvr_eligible: true)
    sign_in_as(@event_manager)

    get vehicles_paperwork_path

    assert_response :success
    rows = css_select("tr.table-detail-row")

    assert_predicate rows, :any?, "no detail rows rendered"
    rows.each do |row|
      assert_includes row["class"].split, "hidden", "a detail row rendered open"
    end
  end

  test "the collapsed row counts the sources it is standing in for" do
    teams(:khaki_team).update!(mvr_eligible: true)
    sign_in_as(@event_manager)

    get vehicles_paperwork_path

    assert_response :success
    # The counts are the whole point of leaving a chip cluster behind rather
    # than a bare "Details" button -- a zero has to stay visible too.
    assert_select "button[aria-controls]", text: /1 team/
    assert_select "button[aria-controls]", text: /0 sign-ups/
    assert_select "button[aria-controls][aria-label*=?]", "is eligible: 1 team"
  end

  test "an empty year says so rather than showing a bare table" do
    sign_in_as(@event_manager)

    get vehicles_paperwork_path

    assert_response :success
    assert_select "table", false
    assert_match(/No one has vehicle paperwork on file/, response.body)
  end

  test "a search that matches no one says so without claiming the year is empty" do
    teams(:khaki_team).update!(mvr_eligible: true)
    sign_in_as(@event_manager)

    get vehicles_paperwork_path(callsign: "nobodyhasthiscallsign")

    assert_response :success
    assert_match(/matched these filters/, response.body)
  end

  test "a filter narrows the table and offers a chip that drops just that one" do
    teams(:khaki_team).update!(mvr_eligible: true)
    sign_in_as(@event_manager)

    get vehicles_paperwork_path(mvr_approval: VehiclePaperworkReport::NOT_APPROVED,
                                mvr_team: "Khaki Delegation")

    assert_response :success
    assert_select "a", text: @vehicle_editor.callsign
    # The chip spells the choice the way the picker did, not the raw param
    # value the URL carries.
    assert_select "a", text: /Motor Vehicle Record approval: Not approved/
    assert_select "a", { text: /not_approved/, count: 0 }
    # Each chip links back with only its own filter removed, the other kept.
    assert_select "a[href*='mvr_team=Khaki']" do |links|
      assert links.any? { |link| link["href"].exclude?("mvr_approval") },
        "the approval chip should drop mvr_approval and keep mvr_team"
    end
  end

  test "the team pickers offer every team on the roster, not just the filtered rows" do
    teams(:khaki_team).update!(mvr_eligible: true)
    teams(:green_dot_cadre).update!(mvr_eligible: true)
    sign_in_as(@event_manager)

    get vehicles_paperwork_path(mvr_team: "Khaki Delegation")

    assert_response :success
    assert_select "select[name=mvr_team] option[value='Green Dot Cadre']"
    assert_select "select[name=mvr_team] option[value='Khaki Delegation'][selected]"
  end

  test "every filter the report accepts has a control on the page" do
    teams(:khaki_team).update!(mvr_eligible: true, pvr_eligible: true)
    sign_in_as(@event_manager)

    get vehicles_paperwork_path

    assert_response :success
    # A filter the report honours but the panel never offers is reachable only
    # by hand-editing the URL.
    VehiclePaperworkReport::FILTER_KEYS.each do |key|
      assert_select "[name=#{key}]", { minimum: 1 }, "no control for the #{key} filter"
    end
  end

  test "granted and signed-up positions are labelled apart in the detail row" do
    positions(:khaki_supervisor).update!(mvr_eligible: true)       # held by vehicle_editor
    position = positions(:ood_position)
    position.update!(pvr_eligible: true)
    Slot.create!(position:,
                 begins: Time.zone.local(YEAR, 8, 26, 18, 45, 0),
                 ends: Time.zone.local(YEAR, 8, 26, 22, 45, 0),
                 max: 10, active: true)
      .then { |slot| PersonSlot.create!(person: @vehicle_editor, slot:) }
    sign_in_as(@event_manager)

    get vehicles_paperwork_path

    assert_response :success
    # The Motor Vehicle Record side reads grants, the personal vehicle side
    # sign-ups; one label for both would call a grant a sign-up.
    assert_select "tbody td", text: /Granted positions:\s*Khaki Supervisor/
    assert_select "tbody td", text: /Signed-up positions:\s*#{Regexp.escape(position.title)}/
    assert_select "button[aria-controls]", text: /2 positions/
  end

  test "an eligible sign-up renders with its date in the HTML table" do
    position = positions(:ood_position)
    position.update!(mvr_signup_eligible: true)
    Slot.create!(position:,
                 begins: Time.zone.local(YEAR, 8, 26, 18, 45, 0),
                 ends: Time.zone.local(YEAR, 8, 26, 22, 45, 0),
                 max: 10, active: true)
      .then { |slot| PersonSlot.create!(person: @vehicle_editor, slot:) }

    sign_in_as(@event_manager)

    get vehicles_paperwork_path

    assert_response :success
    # slot.begins arrives as an untyped SQL alias and is formatted only here --
    # the CSV path has its own formatter, so this is the one guard on the
    # rendered sign-up cell.
    assert_select "tbody td", text: /#{Regexp.escape(position.title)}.*Aug 26.*18:45/
  end

  test "a nonsense filter value narrows nothing rather than erroring" do
    teams(:khaki_team).update!(mvr_eligible: true)
    sign_in_as(@event_manager)

    get vehicles_paperwork_path(mvr_approval: "nonsense", mvr_team: "no such team",
                                view: "a filter that no longer exists")

    assert_response :success
    # An unrecognised approval value matches neither side of the yes/no split,
    # so it empties the table -- honest. An unknown team simply matches no one.
    # Neither may raise, and an unpermitted param must be ignored outright.
    assert_select "a", { text: @vehicle_editor.callsign, count: 0 }
    assert_match(/matched these filters/, response.body)
  end

  test "a year before the floor falls back to the current year" do
    sign_in_as(@event_manager)

    get vehicles_paperwork_path(year: 1998)

    assert_response :success
    assert_match(/bring a personal one in #{Current.year}/, response.body)
  end

  test "a past year reads teams and grants as not checked rather than showing today's" do
    teams(:khaki_team).update!(mvr_eligible: true)
    positions(:khaki_supervisor).update!(mvr_eligible: true)       # held by vehicle_editor
    PersonEvent.create!(person_id: @vehicle_editor.id, year: YEAR - 1,
                        signed_motorpool_agreement: true)
    sign_in_as(@event_manager)

    get vehicles_paperwork_path(year: YEAR - 1)

    assert_response :success
    assert_match(/Some of this is today's information/, response.body)
    assert_select "tbody td", text: /Teams:\s*Not checked/
    assert_select "tbody td", text: /Granted positions:\s*Not checked/
    assert_select "tbody td", { text: /Khaki Delegation|Khaki Supervisor/, count: 0 }
    # Sign-ups are the year's own, so the personal vehicle side still reads
    # them -- and the chip names the only kind of position it counted.
    assert_select "tbody td", { text: /Signed-up positions:\s*Not checked/, count: 0 }
    assert_select "button[aria-controls]", text: /0 signed-up positions/
  end

  test "today's team membership does not put anyone in a past year's roster" do
    teams(:khaki_team).update!(mvr_eligible: true)
    sign_in_as(@event_manager)

    get vehicles_paperwork_path(year: YEAR - 1)

    assert_response :success
    # The only thing listing this person is a team they are on NOW; person_team
    # keeps no history, so they were not necessarily on it in YEAR - 1.
    assert_select "a", { text: @vehicle_editor.callsign, count: 0 }
  end

  test "the current year carries no such warning" do
    teams(:khaki_team).update!(mvr_eligible: true)
    sign_in_as(@event_manager)

    get vehicles_paperwork_path

    assert_response :success
    assert_no_match(/Some of this is today's information/, response.body)
    assert_select "tbody td", { text: /Not checked/, count: 0 }
  end

  # The card lists what puts a person on the list. A team or a granted position
  # does that for the current year only, so a past year's card leaves both out.
  test "the card names teams and granted positions only for the current year" do
    question = "Who appears in this report?"
    sign_in_as(@event_manager)

    get vehicles_paperwork_path

    assert_match(/Belongs to a team.*Holds a position/, card_answer(question))

    get vehicles_paperwork_path(year: YEAR - 1)

    answer = card_answer(question)
    assert_match(/Signed the Vehicle Use Protocol/, answer)
    assert_no_match(/Belongs to a team|Holds a position/, answer)
  end

  # ------------------------------------------------------------------ csv ----

  test "the export carries every column whatever the view is" do
    teams(:khaki_team).update!(mvr_eligible: true, pvr_eligible: true)
    positions(:khaki_supervisor).update!(mvr_eligible: true)       # held by vehicle_editor
    position = positions(:ood_position)
    position.update!(mvr_signup_eligible: true)
    slot = Slot.create!(position:,
                        begins: Time.zone.local(YEAR, 8, 26, 18, 45, 0),
                        ends: Time.zone.local(YEAR, 8, 26, 22, 45, 0),
                        max: 10, active: true)
    PersonSlot.create!(person: @vehicle_editor, slot:)
    PersonEvent.create!(person_id: @vehicle_editor.id, year: YEAR,
                        signed_motorpool_agreement: true)

    sign_in_as(@event_manager)

    get vehicles_paperwork_path(format: :csv)

    assert_response :success
    assert_equal "text/csv; charset=utf-8", response.media_type + "; charset=" + response.charset

    lines = response.body.split("\n")

    assert_equal 14, Vehicles::PaperworkController::CSV_HEADERS.size
    assert_equal "Callsign,Status,Vehicle Use Protocol,Motor Vehicle Record Approved," \
                 "Motor Vehicle Record Eligible,Motor Vehicle Record Checkbox," \
                 "Motor Vehicle Record Teams,Motor Vehicle Record Granted Positions," \
                 "Motor Vehicle Record Eligible Sign-Ups,Personal Vehicle Agreement," \
                 "Personal Vehicle Eligible,Personal Vehicle Teams," \
                 "Personal Vehicle Signed-Up Positions,Personal Vehicle Checkbox",
                 lines.first,
                 "header row -- spelled out rather than compared against the constant " \
                 "that produced it, which would pass however the columns were ordered"

    row = lines.find { |line| line.start_with?(@vehicle_editor.callsign) }

    assert_not_nil row, "the eligible ranger should be exported"
    # Positional, so swapping any two entries in csv_row fails here. "Y"/"N"
    # matches upstream's export and the ticketing CSV controllers.
    assert_equal "#{@vehicle_editor.callsign},#{@vehicle_editor.status},Y,N,Y,N," \
                 "Khaki Delegation,Khaki Supervisor,#{position.title} 2026-08-26 18:45," \
                 "N,Y,Khaki Delegation,,N",
                 row
  end

  test "the export narrows with the filters the reader set" do
    teams(:khaki_team).update!(mvr_eligible: true)
    teams(:green_dot_cadre).update!(mvr_eligible: true)
    sign_in_as(@event_manager)

    get vehicles_paperwork_path(format: :csv, mvr_team: "Khaki Delegation")

    assert_response :success

    lines = response.body.split("\n")

    assert_equal 2, lines.size, "headers plus the one Khaki member"
    assert lines.last.start_with?(@vehicle_editor.callsign)
  end

  test "a past year's export says the team and granted-position columns were never checked" do
    teams(:khaki_team).update!(mvr_eligible: true, pvr_eligible: true)
    PersonEvent.create!(person_id: @vehicle_editor.id, year: YEAR - 1,
                        signed_motorpool_agreement: true)
    sign_in_as(@event_manager)

    get vehicles_paperwork_path(format: :csv, year: YEAR - 1)

    assert_response :success

    row = response.body.split("\n").find { |line| line.start_with?(@vehicle_editor.callsign) }

    assert_not_nil row
    # A blank cell would read as a confirmed "none"; person_team and
    # person_position keep no history, so nothing was ever looked up for this
    # year. Sign-ups are the year's own and stay blank when there are none.
    assert_equal "#{@vehicle_editor.callsign},#{@vehicle_editor.status},Y,N,N,N," \
                 "not checked,not checked,,N,N,not checked,,N",
                 row
  end

  test "the export narrows with the search the reader typed" do
    teams(:khaki_team).update!(mvr_eligible: true)
    sign_in_as(@event_manager)

    get vehicles_paperwork_path(format: :csv, callsign: "nobodyhasthiscallsign")

    assert_response :success
    assert_equal 1, response.body.split("\n").size, "headers only"
  end
end
