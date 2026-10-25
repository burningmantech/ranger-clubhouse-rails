# frozen_string_literal: true

require "test_helper"

class Autocomplete::VehicleAdapterTest < ActiveSupport::TestCase
  setup do
    @person = person(:active_ranger)
    Current.person = @person
    Current.roles_manager = RoleManager.retrieve(@person)
  end

  test "matches an approved vehicle by license number in the current year" do
    adapter = Autocomplete::VehicleAdapter.new(query: "!RANGER1", mode: "vehicle", limit: 5)
    result = adapter.search

    ids = result[:items].map { |i| i[:meta][:id] }
    assert_includes ids, vehicle(:approved_owner_vehicle).id
    assert_equal 1, result[:groups].size
    assert_equal "vehicle", result[:groups].first[:key]
  end

  test "matches license, rental, or sticker columns" do
    sticker = Autocomplete::VehicleAdapter.new(query: "!PERMIT100", mode: "vehicle").search
    assert_includes sticker[:items].map { |i| i[:meta][:id] }, vehicle(:approved_owner_vehicle).id

    rental = Autocomplete::VehicleAdapter.new(query: "!DPW5550", mode: "vehicle").search
    assert_includes rental[:items].map { |i| i[:meta][:id] }, vehicle(:approved_fleet_vehicle).id
  end

  test "excludes non-approved vehicles" do
    result = Autocomplete::VehicleAdapter.new(query: "!PENDING9", mode: "vehicle").search

    assert_empty result[:items]
    assert_equal "No vehicles found for the 2026 event.", result[:empty_text]
  end

  test ":<year> suffix scopes the search year" do
    current = Autocomplete::VehicleAdapter.new(query: "!OLDYEAR1", mode: "vehicle").search
    assert_empty current[:items], "OLDYEAR1 is a 2024 vehicle; current-year search should miss"

    scoped = Autocomplete::VehicleAdapter.new(query: "!OLDYEAR1:2024", mode: "vehicle").search
    assert_includes scoped[:items].map { |i| i[:meta][:id] }, vehicle(:approved_vehicle_2024).id
  end

  test "non-4-digit year suffix returns empty" do
    result = Autocomplete::VehicleAdapter.new(query: "!RANGER1:24", mode: "vehicle").search

    assert_empty result[:items]
  end

  test "post-strip number below min length returns empty without matching all rows" do
    result = Autocomplete::VehicleAdapter.new(query: "!A", mode: "vehicle").search

    assert_empty result[:items]
    assert_equal [], result[:flat_item_ids]
  end

  test "year-specific empty text" do
    result = Autocomplete::VehicleAdapter.new(query: "!ZZZZZZ:2024", mode: "vehicle").search

    assert_equal "No vehicles found for the 2024 event.", result[:empty_text]
  end

  test "renders owner, team, and fleet labels" do
    owner = Autocomplete::VehicleAdapter.new(query: "!RANGER1", mode: "vehicle").search
    assert_match(/Owner TestRanger/, owner[:items].first[:html])

    fleet = Autocomplete::VehicleAdapter.new(query: "!DPW5550", mode: "vehicle").search
    assert_match(/Team Logistics/, fleet[:items].first[:html])
  end

  test "owned vehicle links to the owner's vehicle list; team/fleet vehicles are unlinked" do
    owned = Autocomplete::VehicleAdapter.new(query: "!RANGER1", mode: "vehicle").search
    owner_vehicle = vehicle(:approved_owner_vehicle)
    assert_equal Rails.application.routes.url_helpers.person_vehicles_path(owner_vehicle.person_id), owned[:items].first[:url]

    team = Autocomplete::VehicleAdapter.new(query: "!DPW5550", mode: "vehicle").search
    assert_nil team[:items].first[:url], "team/fleet vehicles have no owner and are not linked"
  end

  test "emits the unified envelope shape with a single group and no filters" do
    result = Autocomplete::VehicleAdapter.new(query: "!RANGER1", mode: "vehicle").search

    assert_equal [], result[:filters]
    assert_equal 1, result[:groups].size
    assert_equal result[:flat_item_ids].sort, result[:groups].first[:item_ids].sort
    item = result[:items].first
    assert item[:id].present?
    assert item[:value].present?
    assert item[:label].present?
    assert item[:html].present?
    assert item[:meta].is_a?(Hash)
  end

  # D2 GUARD: a person whose callsign equals a vehicle number must NEVER be returned,
  # and the search must NEVER carry a person_id into the query.
  test "D2 guard: never returns a person whose callsign equals the vehicle number" do
    collision = person(:plate_collision_ranger)
    assert_equal "RANGER1", collision.callsign

    result = Autocomplete::VehicleAdapter.new(query: "!RANGER1", mode: "vehicle").search

    # Every returned item is a vehicle item (id-prefixed "v"); none is a person.
    assert result[:items].all? { |i| i[:id].start_with?("v") }
    returned_record_ids = result[:items].map { |i| i[:meta][:id] }
    assert_not_includes returned_record_ids, collision.id
    # The only matched record is the vehicle, not the colliding person.
    assert_equal [vehicle(:approved_owner_vehicle).id], returned_record_ids
  end

  # D2: results are not scoped to the searching person — a vehicle owned by any person
  # is returned purely on its own column match, never filtered by person_id.
  test "D2 guard: results are not scoped to the current person_id" do
    # active_ranger is the "current" person via setup, but the matched vehicle's owner
    # is independent of who is searching; matching is by license number only.
    Current.person = person(:retired_ranger)
    Current.roles_manager = RoleManager.retrieve(Current.person)

    result = Autocomplete::VehicleAdapter.new(query: "!RANGER1", mode: "vehicle").search

    # Still found despite the searcher not owning it -> no person_id scoping.
    assert_equal [vehicle(:approved_owner_vehicle).id], result[:items].map { |i| i[:meta][:id] }
  end
end
