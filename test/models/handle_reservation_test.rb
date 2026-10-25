# frozen_string_literal: true

require "test_helper"

class HandleReservationTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 8, 12, 0, 0)
    Current.reset
    Current.person = person(:auditor_ranger)
    ActionLog.delete_all
    HandleReservation.delete_all
  end

  teardown do
    Current.reset
    travel_back
  end

  test "normalizes handle and coerces blank values" do
    reservation = HandleReservation.create!(
      handle: "  D O O D  ",
      reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM,
      reason: nil,
      expires_on: "",
      twii_year: ""
    )

    assert_equal "D O O D", reservation.handle
    assert_equal "dood", reservation.normalized_handle
    assert_equal "", reservation.reason
    assert_nil reservation.expires_on
    assert_nil reservation.twii_year
  end

  test "twii reservations require a year and default expires_on to september 15 two years out" do
    reservation = HandleReservation.new(
      handle: "Twii One",
      reservation_type: HandleReservation::RESERVATION_TYPE_TWII_PERSON
    )

    assert_not reservation.valid?
    assert_includes reservation.errors[:twii_year], "TWII year can't be blank."

    reservation.twii_year = 2026
    assert reservation.valid?
    assert_equal Date.new(2028, 9, 15), reservation.expires_on
  end

  test "twii default expiry leaves explicit and invalid dates alone" do
    explicit = HandleReservation.new(
      handle: "Twii Explicit",
      reservation_type: HandleReservation::RESERVATION_TYPE_TWII_PERSON,
      twii_year: 2026,
      expires_on: "2027-01-02"
    )
    assert explicit.valid?
    assert_equal Date.new(2027, 1, 2), explicit.expires_on

    garbled = HandleReservation.new(
      handle: "Twii Garbled",
      reservation_type: HandleReservation::RESERVATION_TYPE_TWII_PERSON,
      twii_year: 2026,
      expires_on: "2027-02-31"
    )
    assert_not garbled.valid?
    assert_includes garbled.errors[:expires_on], "The expiration date is not a valid date."

    other_type = HandleReservation.new(
      handle: "Not Twii",
      reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM
    )
    assert other_type.valid?
    assert_nil other_type.expires_on
  end

  test "invalid dates are rejected" do
    reservation = HandleReservation.new(
      handle: "Bad Date",
      reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM
    )
    reservation.expires_on = "2026-02-31"

    assert_not reservation.valid?
    assert_includes reservation.errors[:expires_on], "The expiration date is not a valid date."
  end

  test "find_for_query filters active and expired rows using indifferent access" do
    no_expiry = HandleReservation.create!(
      handle: "Always Active",
      reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM
    )
    future = HandleReservation.create!(
      handle: "Future Active",
      reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM,
      expires_on: Current.today + 1.day
    )
    expired = HandleReservation.create!(
      handle: "Expired Handle",
      reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM,
      expires_on: Current.today - 1.day
    )

    active_rows = HandleReservation.findForQuery("active" => true).to_a
    expired_rows = HandleReservation.find_for_query(expired: true).to_a

    assert_equal [no_expiry, future].map(&:id).sort, active_rows.map(&:id).sort
    assert_equal [expired.id], expired_rows.map(&:id)
  end

  test "retrieve helpers group and filter by normalized handle" do
    active = HandleReservation.create!(
      handle: "D O O D",
      reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM
    )
    expired = HandleReservation.create!(
      handle: "DOOD",
      reservation_type: HandleReservation::RESERVATION_TYPE_BRC_TERM,
      expires_on: Current.today - 1.day
    )

    grouped = HandleReservation.retrieveActiveByHandle
    rows = HandleReservation.retrieveAllByNormalizedHandle("dood")

    assert_equal [active.id], grouped.fetch("dood").map(&:id)
    assert_equal [active.id], rows.map(&:id)
    assert HandleReservation.handleTypeExists("DOOD", HandleReservation::RESERVATION_TYPE_RANGER_TERM, nil)
    assert_not HandleReservation.handle_type_exists?("DOOD", HandleReservation::RESERVATION_TYPE_TWII_PERSON, 2026)
    assert HandleReservation.exists?(expired.id)
  end

  test "type labels and expiry helpers are available through primary and compatibility APIs" do
    reservation = HandleReservation.create!(
      handle: "Old News",
      reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM,
      expires_on: Current.today - 1.day
    )

    assert_equal "Ranger term", reservation.type_label
    assert_equal "Ranger term", reservation.getTypeLabel
    assert reservation.has_expired?
    assert_equal HandleReservation::RESERVATION_TYPE_TWII_PERSON, HandleReservation::TYPE_TWII_PERSON
  end

  test "non twii reservations collide on normalized handle and type" do
    HandleReservation.create!(
      handle: "D O O D",
      reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM
    )

    duplicate = HandleReservation.new(
      handle: "DOOD",
      reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:handle], "has already been reserved for this type"
  end

  test "twii reservations collide on normalized handle type and year" do
    HandleReservation.create!(
      handle: "Twii One",
      reservation_type: HandleReservation::RESERVATION_TYPE_TWII_PERSON,
      twii_year: 2025
    )

    duplicate = HandleReservation.new(
      handle: "TWII ONE",
      reservation_type: HandleReservation::RESERVATION_TYPE_TWII_PERSON,
      twii_year: 2025
    )
    different_year = HandleReservation.new(
      handle: "TWII ONE",
      reservation_type: HandleReservation::RESERVATION_TYPE_TWII_PERSON,
      twii_year: 2026
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:handle], "has already been reserved for this type and year"
    assert different_year.valid?
  end

  test "record_deceased creates a normalized reservation once" do
    HandleReservation.recordDeceased("Some Ranger")

    reservation = HandleReservation.find_by(reservation_type: HandleReservation::RESERVATION_TYPE_DECEASED_PERSON)

    assert_not_nil reservation
    assert_equal WordUtils.normalize_word("Some Ranger"), reservation.normalized_handle
    assert_match(/marked deceased by AuditorTest on 2026-04-08/, reservation.reason)

    assert_no_difference("HandleReservation.count") do
      HandleReservation.record_deceased("Some Ranger")
    end
  end

  test "audit writes action logs for create update destroy and expiry" do
    reservation = nil

    assert_difference("ActionLog.count", 1) do
      reservation = HandleReservation.create!(
        handle: "Audit Trail",
        reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM
      )
    end

    create_log = ActionLog.order(:id).last
    assert_equal "handle-reservation-create", create_log.event
    assert_equal Current.person_id, create_log.person_id
    assert_nil create_log.target_person_id
    assert_equal "", create_log.message
    assert_equal reservation.id, create_log.data["id"]
    assert_equal "Audit Trail", create_log.data["handle"]
    assert_equal "audittrail", create_log.data["normalized_handle"]
    assert_instance_of String, create_log.data["created_at"]

    ActionLog.delete_all

    assert_difference("ActionLog.count", 1) do
      reservation.audit_reason = "manual update"
      reservation.update!(reason: "updated")
    end

    update_log = ActionLog.order(:id).last
    assert_equal "handle-reservation-update", update_log.event
    assert_equal "manual update", update_log.message
    assert_equal reservation.id, update_log.data["id"]
    assert_equal ["", "updated"], update_log.data["reason"]

    ActionLog.delete_all

    assert_difference("ActionLog.count", 1) do
      reservation.audit_reason = "manual delete"
      reservation.destroy!
    end

    destroy_log = ActionLog.order(:id).last
    assert_equal "handle-reservation-delete", destroy_log.event
    assert_equal "manual delete", destroy_log.message
    assert_equal reservation.id, destroy_log.data["id"]
    assert_equal "updated", destroy_log.data["reason"]

    ActionLog.delete_all

    expiring = HandleReservation.create!(
      handle: "Expired Audit",
      reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM,
      expires_on: Current.today - 1.day
    )
    ActionLog.delete_all

    assert_difference("ActionLog.count", 1) do
      payload = HandleReservation.expire_handles!

      assert_equal ["Expired Audit"], payload.map { |row| row["handle"] }
    end

    expiry_log = ActionLog.order(:id).last
    assert_equal "handle-reservation-delete", expiry_log.event
    assert_equal "expire handle", expiry_log.message
    assert_equal expiring.id, expiry_log.data["id"]
    assert_equal "Expired Audit", expiry_log.data["handle"]
    assert_not HandleReservation.exists?(expiring.id)
  end

  test "audit_user_id overrides Current.person_id" do
    reservation = HandleReservation.new(
      handle: "Override Actor",
      reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM
    )
    reservation.audit_user_id = person(:active_ranger).id

    assert_difference("ActionLog.count", 1) do
      reservation.save!
    end

    assert_equal person(:active_ranger).id, ActionLog.order(:id).last.person_id
  end
end
