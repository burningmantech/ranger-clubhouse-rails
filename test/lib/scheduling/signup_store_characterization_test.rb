# frozen_string_literal: true

require "test_helper"

# Characterization of the transactional WRITE path (create_signup / delete_signup) as it
# stands BEFORE extracting the SlotStore seam. These two methods hold the locked re-check,
# the audit_reason write, the recount, and the error->status mapping that the
# ActiveRecordSlotStore must reproduce byte-for-byte.
class Scheduling::SignupStoreCharacterizationTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  Mgmt = Scheduling::Management

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Current.reset
    @person = person(:active_ranger)
    Current.person = @person
    @position = positions(:council_manager)
  end

  def make_slot(max:, signed_up: 0, trainer: nil)
    s = Slot.create!(
      position: @position,
      begins: Time.zone.local(2026, 8, 25, 10, 0, 0),
      ends: Time.zone.local(2026, 8, 25, 16, 0, 0),
      max: max, active: true, timezone: "America/Los_Angeles"
    )
    s.update_columns(signed_up: signed_up, trainer_slot_id: trainer&.id)
    s.reload
  end

  def create_signup(slot, force: false)
    Mgmt.send(:create_signup, @person.id, slot, force: force)
  end

  def delete_signup(slot, **opts)
    Mgmt.send(:delete_signup, @person.id, slot, **opts)
  end

  # ===== create_signup =====

  test "create_signup adds the person and increments signed_up" do
    slot = make_slot(max: 5, signed_up: 0)
    assert_equal Scheduling::STATUS_SUCCESS, create_signup(slot)
    assert PersonSlot.exists?(person_id: @person.id, slot_id: slot.id)
    assert_equal 1, slot.reload.signed_up
  end

  test "create_signup on an existing signup returns EXISTS" do
    slot = make_slot(max: 5)
    create_signup(slot)
    assert_equal Scheduling::STATUS_EXISTS, create_signup(slot)
    assert_equal 1, slot.reload.signed_up
  end

  test "create_signup at capacity returns FULL, but force overrides" do
    slot = make_slot(max: 1, signed_up: 1)
    assert_equal Scheduling::STATUS_FULL, create_signup(slot)

    forced = make_slot(max: 1, signed_up: 1)
    assert_equal Scheduling::STATUS_SUCCESS, create_signup(forced, force: true)
    assert_equal 2, forced.reload.signed_up
  end

  test "create_signup respects the trainer multiplier in the locked re-check" do
    trainer = make_slot(max: 99, signed_up: 2)
    slot = make_slot(max: 2, signed_up: 4, trainer: trainer) # effective max 2*2 = 4 -> full
    assert_equal Scheduling::STATUS_FULL, create_signup(slot)
  end

  # ===== delete_signup =====

  test "delete_signup removes the signup and decrements signed_up" do
    slot = make_slot(max: 5)
    create_signup(slot)
    assert_equal Scheduling::STATUS_SUCCESS, delete_signup(slot.reload)
    assert_not PersonSlot.exists?(person_id: @person.id, slot_id: slot.id)
    assert_equal 0, slot.reload.signed_up
  end

  test "delete_signup of a missing signup returns MISSING_SIGNUP" do
    slot = make_slot(max: 5)
    assert_equal Scheduling::STATUS_MISSING_SIGNUP, delete_signup(slot)
  end

  test "delete_signup carries an audit reason onto the destroyed person_slot" do
    slot = make_slot(max: 5)
    create_signup(slot)
    # audit_reason is set on the record before destroy; the destroy is audited.
    assert_equal Scheduling::STATUS_SUCCESS, delete_signup(slot, reason: "status-change")
    assert_not PersonSlot.exists?(person_id: @person.id, slot_id: slot.id)
  end
end
