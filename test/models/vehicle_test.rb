# frozen_string_literal: true

require "test_helper"

# Guards the two validation-ordering rules the registry depends on. Both were
# broken until the registry port exercised them: nothing else in the app ever
# created a fleet vehicle, or a personal vehicle from a callsign, through the
# ActiveRecord layer.
class VehicleTest < ActiveSupport::TestCase
  test "a fleet vehicle saves without an owner" do
    vehicle = Vehicle.new(type: Vehicle::FLEET,
                          event_year: 2026,
                          team_assignment: "Logistics",
                          vehicle_make: "GMC",
                          vehicle_model: "Sierra",
                          vehicle_color: "Green")

    assert vehicle.save, vehicle.errors.full_messages.join(", ")
    assert_nil vehicle.person_id
  end

  test "a personal vehicle resolves its owner from the callsign alone" do
    person = person(:active_ranger)

    vehicle = Vehicle.new(type: Vehicle::PERSONAL,
                          callsign: person.callsign,
                          event_year: 2026,
                          vehicle_make: "Subaru",
                          vehicle_model: "Outback",
                          vehicle_color: "Blue")

    assert vehicle.save, vehicle.errors.full_messages.join(", ")
    assert_equal person.id, vehicle.person_id
  end

  test "an unknown callsign is rejected rather than silently dropped" do
    vehicle = Vehicle.new(type: Vehicle::PERSONAL,
                          callsign: "NoSuchCallsignAnywhere",
                          event_year: 2026,
                          vehicle_make: "Ford",
                          vehicle_model: "F-350",
                          vehicle_color: "White")

    assert_not vehicle.save
    assert_includes vehicle.errors[:callsign], "Callsign not found."
  end

  test "a personal vehicle with neither callsign nor owner reports the missing callsign" do
    vehicle = Vehicle.new(type: Vehicle::PERSONAL,
                          event_year: 2026,
                          vehicle_make: "Ford",
                          vehicle_model: "F-350",
                          vehicle_color: "White")

    assert_not vehicle.save
    assert_includes vehicle.errors[:callsign], "Missing callsign."
  end

  test "a record with no type at all still reports the missing callsign, not a bare person_id error" do
    # normalize_fields defaults type to PERSONAL, and must run before the
    # callsign check so the error names the field the form actually shows.
    vehicle = Vehicle.new(event_year: 2026,
                          vehicle_make: "Ford",
                          vehicle_model: "F-350",
                          vehicle_color: "White")

    assert_not vehicle.save
    assert_includes vehicle.errors[:callsign], "Missing callsign."
  end

  test "fleet vehicles are force-approved on save" do
    vehicle = Vehicle.create!(type: Vehicle::FLEET,
                              status: Vehicle::PENDING,
                              event_year: 2026,
                              team_assignment: "Logistics",
                              vehicle_make: "GMC",
                              vehicle_model: "Sierra",
                              vehicle_color: "Green")

    assert_equal Vehicle::APPROVED, vehicle.status
  end

  # A request whose owner account is gone has no callsign, and the list is
  # ordered by callsign. Left in, it stopped the reviewers' nightly mail from
  # being built at all.
  test "find_all_pending skips a request whose owner is gone" do
    kept = vehicle(:pending_vehicle)
    orphan = Vehicle.create!(person: person(:active_ranger), type: Vehicle::PERSONAL,
                             status: Vehicle::PENDING, event_year: kept.event_year,
                             license_number: "GHOST01", vehicle_make: "Ford",
                             vehicle_model: "Ranger", vehicle_color: "Grey")
    orphan.update_column(:person_id, 0)

    pending = Vehicle.find_all_pending

    assert_includes pending.map(&:id), kept.id
    assert_not_includes pending.map(&:id), orphan.id
  end
end
