# frozen_string_literal: true

require "test_helper"

class Vehicles::RegistryControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers
  include PersonTestFactory

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    Vehicle.delete_all
    AccessDocument.delete_all

    @admin = person(:auditor_ranger)
    @editor = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @unauthorized = person(:ranger_with_custom_gender)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::VEHICLE_INFO_UPDATE, "Vehicle Info Update")
    ensure_role(Role::TRAINER, "Trainer")

    grant_role(@admin, Role::ADMIN)
    grant_role(@editor, Role::EVENT_MANAGEMENT)
    grant_role(@editor, Role::VEHICLE_INFO_UPDATE)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
    grant_role(@unauthorized, Role::TRAINER)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- gates ----

  test "an anonymous visitor is sent to the login page" do
    get vehicles_registry_index_path

    assert_redirected_to root_path
  end

  test "a user with no relevant role cannot reach the registry" do
    sign_in_as(@unauthorized)

    get vehicles_registry_index_path

    assert_redirected_to me_root_path
  end

  test "event management can view the roster but cannot edit records" do
    vehicle = create_fleet_vehicle

    sign_in_as(@event_manager)

    get vehicles_registry_index_path
    assert_response :success

    get new_vehicles_registry_path
    assert_redirected_to vehicles_registry_index_path(year: Current.year)

    get edit_vehicles_registry_path(vehicle)
    assert_redirected_to vehicles_registry_index_path(year: Current.year)
  end

  test "vehicle info update holders may edit but not delete" do
    vehicle = create_fleet_vehicle

    sign_in_as(@editor)

    get edit_vehicles_registry_path(vehicle)
    assert_response :success

    delete vehicles_registry_path(vehicle)
    assert_redirected_to vehicles_registry_index_path(year: Current.year)
    assert Vehicle.exists?(vehicle.id), "the record should survive a denied delete"
  end

  test "an admin may delete a vehicle" do
    vehicle = create_fleet_vehicle

    sign_in_as(@admin)

    delete vehicles_registry_path(vehicle)

    assert_not Vehicle.exists?(vehicle.id)
  end

  test "every viewer may reach the permit page" do
    vehicle = create_fleet_vehicle

    sign_in_as(@event_manager)

    get permit_vehicles_registry_path(vehicle)

    assert_response :success
  end

  # ----------------------------------------------------------------- sort ----

  test "fleet sorts by team and personal by callsign, interleaved and case-insensitive" do
    # The expected order is spelled out rather than derived from the roster:
    # asserting that the returned keys are sorted only restates sort_by and
    # passes for any implementation, including one that sorts by the wrong field.
    create_fleet_vehicle(team_assignment: "zebra", make: "Ford")
    create_fleet_vehicle(team_assignment: "Alpha", make: "GMC")
    create_personal_vehicle(person: @editor, make: "Subaru")

    sign_in_as(@event_manager)
    get vehicles_registry_index_path

    # Fleet rows key off the team, personal rows off the callsign, in one list.
    makes_by_owner = { "Alpha" => "GMC", @editor.callsign => "Subaru", "zebra" => "Ford" }
    expected = makes_by_owner.keys.sort_by(&:downcase)

    assert_equal expected.map(&:downcase), assigns_rows.map(&:sort_key)
    assert_equal expected.map { |owner| makes_by_owner[owner] }, assigns_rows.map(&:vehicle_make)
  end

  test "a legacy fleet vehicle with no team sorts ahead of the named ones" do
    # Validation requires a team on new fleet records, but rows predating the
    # rule exist, and upstream's comparator has always had this fallback.
    legacy = Vehicle.new(type: Vehicle::FLEET, team_assignment: "", event_year: Current.year)

    assert_equal "1a", VehicleRegistry::Row.new(legacy).sort_key
  end

  # -------------------------------------------------------------- filters ----

  test "the status filter narrows the roster" do
    create_fleet_vehicle                                   # forced to approved
    create_personal_vehicle(person: @editor)               # pending

    sign_in_as(@event_manager)

    get vehicles_registry_index_path(status: Vehicle::PENDING)

    assert_equal [Vehicle::PENDING], assigns_rows.map(&:status).uniq
  end

  test "the type filter narrows the roster" do
    create_fleet_vehicle
    create_personal_vehicle(person: @editor)

    sign_in_as(@event_manager)

    get vehicles_registry_index_path(type: Vehicle::FLEET)

    assert_equal [Vehicle::FLEET], assigns_rows.map(&:type).uniq
  end

  test "applying the filters without changing anything leaves the roster intact" do
    # The picklists submit the shared "all" sentinel for their default option.
    # "all".present? is true, so a naive filter compares it against a real column
    # value, matches nothing, and silently empties the page.
    create_fleet_vehicle
    create_personal_vehicle(person: @editor)

    sign_in_as(@event_manager)

    get vehicles_registry_index_path(status: UiComponents::FilterBarHelper::ALL_FILTER,
                                     type: UiComponents::FilterBarHelper::ALL_FILTER)

    assert_equal 2, assigns_rows.size
  end

  test "a plate typed with its separators still matches the stripped stored value" do
    create_personal_vehicle(person: @editor, license_number: "7ABC123")

    sign_in_as(@event_manager)

    get vehicles_registry_index_path(number: "7ABC-123")

    assert_equal 1, assigns_rows.size
  end

  test "a search of nothing but separators matches nothing" do
    # The plate leg strips the needle to "", and String#include?("") is true for
    # every string -- it would match every plated vehicle while the count line
    # claimed a narrowing.
    create_personal_vehicle(person: @editor, license_number: "7ABC123")

    sign_in_as(@event_manager)

    get vehicles_registry_index_path(number: "-")

    assert_equal 0, assigns_rows.size
  end

  test "the number search also matches permit and DPW request numbers" do
    create_fleet_vehicle(rental_number: "DPW-8821")
    create_personal_vehicle(person: @editor, sticker_number: "PERMIT412")

    sign_in_as(@event_manager)

    get vehicles_registry_index_path(number: "8821")
    assert_equal 1, assigns_rows.size

    get vehicles_registry_index_path(number: "permit412")
    assert_equal 1, assigns_rows.size
  end

  test "the permit filter reads the enum's stray other value as None" do
    # The column allows "other", which no option offers and which the roster
    # already renders as "None" -- matching on the raw value would leave those
    # rows unreachable from a filter whose cells read exactly like theirs.
    create_personal_vehicle(person: @editor, driving_sticker: Vehicle::DRIVING_STICKER_STAFF)
    create_personal_vehicle(person: @event_manager, make: "Ford").update_column(:driving_sticker, "other")

    sign_in_as(@event_manager)

    get vehicles_registry_index_path(permit: Vehicle::DRIVING_STICKER_NONE)
    assert_equal 1, assigns_rows.size

    get vehicles_registry_index_path(permit: Vehicle::DRIVING_STICKER_STAFF)
    assert_equal 1, assigns_rows.size
  end

  test "the item filter matches one item without matching the columns beside it" do
    create_personal_vehicle(person: @editor, ranger_logo: Vehicle::LOGO_EVENT)
    create_personal_vehicle(person: @event_manager, make: "Ford", fuel_chit: Vehicle::FUEL_CHIT_EVENT)

    sign_in_as(@event_manager)

    # Both rows hold "event", in different columns.
    get vehicles_registry_index_path(item: "ranger_logo:#{Vehicle::LOGO_EVENT}")
    assert_equal ["Subaru"], assigns_rows.map(&:vehicle_make)

    get vehicles_registry_index_path(item: "fuel_chit:#{Vehicle::FUEL_CHIT_EVENT}")
    assert_equal ["Ford"], assigns_rows.map(&:vehicle_make)
  end

  test "a column the item filter does not own matches nothing" do
    # The column half of the value arrives from the query string.
    create_personal_vehicle(person: @editor)

    sign_in_as(@event_manager)

    get vehicles_registry_index_path(item: "notes:")
    assert_equal 0, assigns_rows.size
  end

  test "a denied request answers no permit or item filter" do
    # Nothing is issued for it, and the roster blanks both cells.
    create_personal_vehicle(person: @editor,
                            status: Vehicle::REJECTED,
                            driving_sticker: Vehicle::DRIVING_STICKER_STAFF,
                            ranger_logo: Vehicle::LOGO_EVENT)

    sign_in_as(@event_manager)

    get vehicles_registry_index_path(permit: Vehicle::DRIVING_STICKER_STAFF)
    assert_equal 0, assigns_rows.size

    get vehicles_registry_index_path(item: "ranger_logo:#{Vehicle::LOGO_EVENT}")
    assert_equal 0, assigns_rows.size
  end

  test "the Setup Access Pass filter separates the people who have one" do
    create_personal_vehicle(person: @editor)
    create_personal_vehicle(person: @event_manager, make: "Ford")
    create_fleet_vehicle # no owner, so neither answer applies
    AccessDocument.create!(person_id: @editor.id,
                           type: AccessDocument::SAP,
                           status: AccessDocument::CLAIMED,
                           source_year: Current.year,
                           access_any_time: true)

    sign_in_as(@event_manager)

    get vehicles_registry_index_path(sap: VehicleRegistry::SAP_PRESENT)
    assert_equal ["Subaru"], assigns_rows.map(&:vehicle_make)

    get vehicles_registry_index_path(sap: VehicleRegistry::SAP_MISSING)
    assert_equal ["Ford"], assigns_rows.map(&:vehicle_make)
  end

  test "a prior year ignores the Setup Access Pass filter rather than reporting a gap" do
    # No one looked up that year's passes, so every row would report as missing
    # one. The panel hides the filter there; a hand-typed URL must be harmless.
    create_personal_vehicle(person: @editor, year: Current.year - 1)

    sign_in_as(@event_manager)

    get vehicles_registry_index_path(year: Current.year - 1, sap: VehicleRegistry::SAP_MISSING)

    assert_equal 1, assigns_rows.size
  end

  test "applying the filters leaves no all sentinel in the links the page generates" do
    # "all" is present?, so it survives compact_blank; only active_filters drops
    # it. Left in, it rides along in the export and every row action URL.
    create_fleet_vehicle

    sign_in_as(@event_manager)

    get vehicles_registry_index_path(status: UiComponents::FilterBarHelper::ALL_FILTER,
                                     type: UiComponents::FilterBarHelper::ALL_FILTER)

    assert_response :success
    assert_not_includes @response.body, "status=all"
    assert_not_includes @response.body, "type=all"
  end

  test "the pending count describes requests a reviewer can act on" do
    # Fleet records are force-approved and carry no request; one left at pending
    # by an import must not send a reviewer to a row with nothing to decide.
    create_fleet_vehicle.update_column(:status, Vehicle::PENDING)
    create_personal_vehicle(person: @editor)

    sign_in_as(@event_manager)
    get vehicles_registry_index_path

    assert_equal 1, controller.view_assigns["result"].pending_count
  end

  test "the stat boxes count the whole year while a filter is active" do
    create_fleet_vehicle
    create_personal_vehicle(person: @editor)

    sign_in_as(@event_manager)

    get vehicles_registry_index_path(type: Vehicle::FLEET)

    result = controller.view_assigns["result"]
    assert_equal 1, result.rows.size
    assert_equal 2, result.total_count
    assert_equal 1, result.fleet_count
    assert_equal 1, result.personal_count
  end

  # ----------------------------------------------------------- enrichment ----

  test "current-year rows carry the Setup Access Pass and eligibility" do
    create_personal_vehicle(person: @editor)
    AccessDocument.create!(person_id: @editor.id,
                           type: AccessDocument::SAP,
                           status: AccessDocument::CLAIMED,
                           source_year: Current.year,
                           access_any_time: true)

    sign_in_as(@event_manager)
    get vehicles_registry_index_path

    assert assigns_rows.first.arrives_any_time?
    assert_response :success
    assert_not_includes @response.body, "Not checked"
  end

  test "an eligible owner gets a detail row naming every source" do
    team = Team.create!(title: "Green Dot", active: true, mvr_eligible: true, pvr_eligible: true)
    PersonTeam.create!(person_id: @editor.id, team_id: team.id)
    create_personal_vehicle(person: @editor)

    sign_in_as(@event_manager)
    get vehicles_registry_index_path

    row = assigns_rows.first
    assert_equal ["Green Dot"], row.mvr_teams
    assert_equal ["Green Dot"], row.pvr_teams
    assert_includes @response.body, "vehicle-eligibility-#{row.id}"
    assert_includes @response.body, "Motor Vehicle Record eligible via"
  end

  test "a pending request with no eligibility says so instead of offering an empty detail row" do
    create_personal_vehicle(person: @editor)

    sign_in_as(@event_manager)
    get vehicles_registry_index_path

    assert_not_includes @response.body, "vehicle-eligibility-#{assigns_rows.first.id}"
    assert_includes @response.body, "No eligible teams, positions, or sign-ups"
  end

  test "a prior year says the pass was never checked rather than claiming there is none" do
    create_personal_vehicle(person: @editor, year: Current.year - 1)

    sign_in_as(@event_manager)
    get vehicles_registry_index_path(year: Current.year - 1)

    assert_response :success
    assert_includes @response.body, "Not checked"
    assert_not_includes @response.body, "No Setup Access Pass"
  end

  # --------------------------------------------------------------- create ----

  test "a personal vehicle is created from a callsign" do
    sign_in_as(@editor)

    assert_difference "Vehicle.count", 1 do
      post vehicles_registry_index_path, params: { vehicle: personal_params(callsign: @event_manager.callsign) }
    end

    assert_equal @event_manager.id, Vehicle.last.person_id
  end

  test "an unknown callsign is rejected with the error on the page" do
    sign_in_as(@editor)

    assert_no_difference "Vehicle.count" do
      post vehicles_registry_index_path, params: { vehicle: personal_params(callsign: "NoSuchCallsign") }
    end

    assert_response :unprocessable_entity
    assert_includes @response.body, "Callsign not found."
  end

  test "a fleet vehicle is approved and forced to a staff permit on create" do
    sign_in_as(@editor)

    post vehicles_registry_index_path, params: {
      vehicle: fleet_params(driving_sticker: Vehicle::DRIVING_STICKER_PREPOST)
    }

    vehicle = Vehicle.last
    assert_equal Vehicle::APPROVED, vehicle.status
    assert_equal Vehicle::DRIVING_STICKER_STAFF, vehicle.driving_sticker
  end

  test "a patch that omits the type cannot slip a fleet vehicle off the staff permit" do
    # Upstream forces this client-side only, so nothing stops a request that
    # simply leaves :type out.
    vehicle = create_fleet_vehicle

    sign_in_as(@editor)

    patch vehicles_registry_path(vehicle), params: {
      vehicle: { driving_sticker: Vehicle::DRIVING_STICKER_NONE, vehicle_color: "Blue" }
    }

    assert_equal Vehicle::DRIVING_STICKER_STAFF, vehicle.reload.driving_sticker
    assert_equal "Blue", vehicle.vehicle_color
  end

  test "a fleet vehicle never keeps an owner" do
    # The roster names the owner from `type` but reads the Setup Access Pass and
    # personal-vehicle eligibility from `person_id`. A fleet row holding both
    # reports one person's pass under a team's name.
    sign_in_as(@editor)

    post vehicles_registry_index_path, params: {
      vehicle: fleet_params(callsign: @event_manager.callsign)
    }

    assert_nil Vehicle.last.person_id
  end

  test "converting a personal vehicle to fleet drops its former owner" do
    vehicle = create_personal_vehicle(person: @editor)

    sign_in_as(@editor)

    patch vehicles_registry_path(vehicle), params: { vehicle: fleet_params }

    vehicle.reload
    assert_equal Vehicle::FLEET, vehicle.type
    assert_nil vehicle.person_id
  end

  test "an event year the registry cannot browse is rejected" do
    # setup_year clamps the year selector to year_floor..Current.year, so a
    # record saved outside that span appears in no roster and no export.
    sign_in_as(@editor)

    assert_no_difference "Vehicle.count" do
      post vehicles_registry_index_path, params: { vehicle: fleet_params(event_year: Current.year + 5) }
    end

    assert_response :unprocessable_entity
  end

  test "a missing callsign reports one error, naming the field the form shows" do
    sign_in_as(@editor)

    post vehicles_registry_index_path, params: { vehicle: personal_params }

    assert_response :unprocessable_entity
    vehicle = Vehicle.new(personal_params.merge(event_year: Current.year))
    assert_not vehicle.valid?
    assert_equal ["Missing callsign."], vehicle.errors.full_messages
  end

  test "both owner fields are on the form whichever type is selected" do
    # Rendering only the field matching the current type would leave the one the
    # reader just selected missing until a failed submit re-rendered the form.
    sign_in_as(@editor)

    get new_vehicles_registry_path
    assert_response :success
    assert_select "input[name='vehicle[team_assignment]']"
    assert_select "input[name='vehicle[callsign]']"
  end

  test "a duplicate plate for the same year is rejected" do
    create_personal_vehicle(person: @editor, license_number: "7ABC123", license_state: "NV")

    sign_in_as(@editor)

    assert_no_difference "Vehicle.count" do
      post vehicles_registry_index_path, params: {
        vehicle: personal_params(callsign: @event_manager.callsign,
                                 license_number: "7ABC123",
                                 license_state: "NV")
      }
    end

    assert_response :unprocessable_entity
  end

  test "saving a record whose class and state were never recorded leaves them blank" do
    # Both columns default to "". Rendered without an explicit blank option the
    # browser preselects the first entry, and an ordinary edit invents a class
    # and a state the vehicle never had. Asserting a blank option merely exists
    # would not catch that -- the round trip has to run.
    vehicle = create_personal_vehicle(person: @editor)
    assert_equal "", vehicle.vehicle_class
    assert_equal "", vehicle.license_state.to_s

    sign_in_as(@editor)

    get edit_vehicles_registry_path(vehicle)
    assert_response :success
    assert_select "select[name='vehicle[vehicle_class]'] option[selected]", count: 0
    assert_select "select[name='vehicle[license_state]'] option[selected]", count: 0

    patch vehicles_registry_path(vehicle), params: {
      vehicle: personal_params(callsign: @editor.callsign, vehicle_color: "Blue",
                               vehicle_class: "", license_state: "")
    }

    vehicle.reload
    assert_equal "Blue", vehicle.vehicle_color
    assert_equal "", vehicle.vehicle_class
    assert_equal "", vehicle.license_state.to_s
  end

  test "a stored value the option list does not offer survives an ordinary save" do
    # license_state is free text shared with the Laravel side; "NA" (Not
    # Available) is in the real data and is not in CountryStateHelper. Without
    # the value being offered, nothing is selected, the blank option becomes the
    # browser default, and merely opening the record and saving erases it.
    vehicle = create_personal_vehicle(person: @editor, license_state: "NA", license_number: "TBD")

    sign_in_as(@editor)

    get edit_vehicles_registry_path(vehicle)
    assert_response :success
    assert_select "select[name='vehicle[license_state]'] option[value='NA'][selected]"

    patch vehicles_registry_path(vehicle), params: {
      vehicle: personal_params(callsign: @editor.callsign, vehicle_color: "Blue",
                               license_state: "NA", license_number: "TBD")
    }

    assert_equal "NA", vehicle.reload.license_state
  end

  # --------------------------------------------------------------- permit ----

  test "a pending vehicle warns before the permit number is taken" do
    vehicle = create_personal_vehicle(person: @editor,
                                      driving_sticker: Vehicle::DRIVING_STICKER_STAFF)

    sign_in_as(@event_manager)
    get permit_vehicles_registry_path(vehicle)

    assert_response :success
    assert_includes @response.body, "Pending review"
    assert_select "input[name='vehicle[sticker_number]']"
  end

  test "a denied vehicle says so and offers no permit field" do
    vehicle = create_personal_vehicle(person: @editor, status: Vehicle::REJECTED)

    sign_in_as(@event_manager)
    get permit_vehicles_registry_path(vehicle)

    assert_response :success
    assert_includes @response.body, "Do not issue any stickers or items"
    assert_select "input[name='vehicle[sticker_number]']", count: 0
  end

  test "the permit form changes only the permit number" do
    vehicle = create_personal_vehicle(person: @editor,
                                      status: Vehicle::PENDING,
                                      driving_sticker: Vehicle::DRIVING_STICKER_STAFF)

    sign_in_as(@event_manager)

    patch permit_vehicles_registry_path(vehicle), params: {
      vehicle: { sticker_number: "412", status: Vehicle::APPROVED, notes: "sneaky" }
    }

    vehicle.reload
    assert_equal "412", vehicle.sticker_number
    assert_equal Vehicle::PENDING, vehicle.status
    assert_equal "", vehicle.notes
  end

  test "a denied vehicle refuses a permit number even by direct request" do
    # Hiding the field is not the rule; the rule is that nothing is issued for a
    # denied request. The roster blanks the permit cell for denied rows, so a
    # number written past the view would be invisible on screen and still
    # exported to the sheet the issuing table works from.
    vehicle = create_personal_vehicle(person: @editor, status: Vehicle::REJECTED,
                                      driving_sticker: Vehicle::DRIVING_STICKER_STAFF)

    sign_in_as(@event_manager)

    patch permit_vehicles_registry_path(vehicle), params: { vehicle: { sticker_number: "412" } }

    assert_equal "", vehicle.reload.sticker_number
    assert_redirected_to permit_vehicles_registry_path(vehicle, year: Current.year)
  end

  test "a permit number records against a record that fails today's validations" do
    # Legacy rows predate rules the model enforces now. Recording the number
    # handed over at the window must not depend on repairing an unrelated column
    # the permit page does not even show.
    vehicle = create_fleet_vehicle(driving_sticker: Vehicle::DRIVING_STICKER_STAFF)
    vehicle.update_column(:team_assignment, "")
    assert_not vehicle.reload.valid?

    sign_in_as(@event_manager)

    patch permit_vehicles_registry_path(vehicle), params: { vehicle: { sticker_number: "412" } }

    assert_equal "412", vehicle.reload.sticker_number
  end

  # ------------------------------------------------------------------ csv ----

  test "the csv exports one header row and one row per vehicle" do
    create_fleet_vehicle(team_assignment: "Logistics")

    sign_in_as(@event_manager)
    get vehicles_registry_index_path(format: :csv)

    assert_response :success
    lines = @response.body.split("\n")
    assert_equal "Person/Team", lines.first.split(",").first
    assert_includes lines.last, "Logistics"
  end

  test "every csv row carries exactly one value per header" do
    # A row that drifts out of step with the header shifts every column after
    # the gap, and the sheet still opens. Splitting on commas measures columns
    # only while no cell contains one, so this case deliberately keeps every
    # value separator-free; the quoting case is the test below. The stdlib CSV
    # library is not in the bundle, so there is no parser to reach for.
    create_fleet_vehicle(team_assignment: "Logistics")
    create_personal_vehicle(person: @editor, notes: "clean")

    sign_in_as(@event_manager)
    get vehicles_registry_index_path(format: :csv)

    lines = @response.body.split("\n")
    assert_equal 3, lines.size
    widths = lines.map { |line| line.split(",", -1).size }
    assert_equal [Vehicles::RegistryController::CSV_HEADERS.size], widths.uniq,
                 "csv rows are not all as wide as the header: #{widths.inspect}"
  end

  test "csv cells containing separators are quoted, including the enrichment columns" do
    # notes, responses and team titles are all free text, and the PVR columns
    # join multiple titles with a newline. Unquoted, either would invent a
    # column boundary and shift the rest of the row.
    create_personal_vehicle(person: @editor, notes: "Left, rear light broken")
    team = Team.create!(title: "Green Dot, Sanctuary", active: true, pvr_eligible: true)
    PersonTeam.create!(person_id: @editor.id, team_id: team.id)

    sign_in_as(@event_manager)
    get vehicles_registry_index_path(format: :csv)

    assert_includes @response.body, %("Left, rear light broken")
    assert_includes @response.body, %("Green Dot, Sanctuary")
  end

  test "the csv issues nothing for a denied request" do
    # The roster blanks the permit and items cells for denied rows. The export
    # is the copy carried to the issuing table, so it has to agree.
    create_personal_vehicle(person: @editor,
                            status: Vehicle::REJECTED,
                            driving_sticker: Vehicle::DRIVING_STICKER_STAFF,
                            sticker_number: "412",
                            ranger_logo: Vehicle::LOGO_EVENT,
                            fuel_chit: Vehicle::FUEL_CHIT_EVENT)

    sign_in_as(@event_manager)
    get vehicles_registry_index_path(format: :csv)

    row = @response.body.split("\n").last
    assert_includes row, "rejected"
    assert_not_includes row, "412"
    assert_not_includes row, "Event"
    assert_not_includes row, "Staff"
  end

  test "the csv marks a prior year's enrichment as unchecked rather than empty" do
    # An empty cell in a current-year sheet reads as "confirmed none".
    create_personal_vehicle(person: @editor, year: Current.year - 1)

    sign_in_as(@event_manager)
    get vehicles_registry_index_path(year: Current.year - 1, format: :csv)

    assert_includes @response.body, "not checked"
  end

  # Deleting the owner leaves the vehicle with no person (vehicle.person_id is
  # set NULL by its foreign key); the row still renders and exports.
  test "a vehicle whose owner has been deleted still lists and exports" do
    owner = create_person("Ghost")
    vehicle = create_personal_vehicle(person: owner)
    owner.destroy!
    assert_nil vehicle.reload.person_id

    sign_in_as(@event_manager)

    get vehicles_registry_index_path
    assert_response :success
    assert_includes @response.body, "Owner deleted"

    get vehicles_registry_index_path(format: :csv)
    assert_response :success
    assert_includes @response.body, "Owner deleted"
  end

  # ----------------------------------------------------------------- menu ----

  # The mega menu is its own lazily-loaded page, not part of the dashboard HTML.
  # One sign-in per test: re-authenticating as a second person inside a single
  # integration session leaves the first person's menu in place.
  test "event management is offered the vehicles menu" do
    sign_in_as(@event_manager)
    get me_menu_path

    assert_response :success
    assert_includes @response.body, "Vehicle Registry"
    assert_includes @response.body, vehicles_registry_index_path
  end

  test "a user without event management is not offered the vehicles menu" do
    sign_in_as(@unauthorized)
    get me_menu_path

    assert_response :success
    assert_not_includes @response.body, "Vehicle Registry"
  end

  private

  def assigns_rows
    controller.view_assigns["result"].rows
  end

  def create_fleet_vehicle(team_assignment: "Logistics", make: "GMC", rental_number: "", year: nil, **attributes)
    Vehicle.create!({ type: Vehicle::FLEET,
                      event_year: year || Current.year,
                      team_assignment:,
                      rental_number:,
                      vehicle_make: make,
                      vehicle_model: "Sierra",
                      vehicle_color: "Green" }.merge(attributes))
  end

  def create_personal_vehicle(person:, make: "Subaru", year: nil, **attributes)
    Vehicle.create!({ type: Vehicle::PERSONAL,
                      person_id: person.id,
                      status: Vehicle::PENDING,
                      event_year: year || Current.year,
                      vehicle_make: make,
                      vehicle_model: "Outback",
                      vehicle_color: "Blue" }.merge(attributes))
  end

  def personal_params(**overrides)
    { type: Vehicle::PERSONAL,
      event_year: Current.year,
      vehicle_make: "Ford",
      vehicle_model: "F-350",
      vehicle_color: "White" }.merge(overrides)
  end

  def fleet_params(**overrides)
    { type: Vehicle::FLEET,
      event_year: Current.year,
      team_assignment: "Logistics",
      status: Vehicle::PENDING,
      vehicle_make: "GMC",
      vehicle_model: "Sierra",
      vehicle_color: "Green" }.merge(overrides)
  end
end
