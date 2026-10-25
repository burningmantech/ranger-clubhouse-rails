# frozen_string_literal: true

require "test_helper"

# Golden-master characterization of the per-person bulk removals
# (remove_future_sign_ups / remove_future_sign_ups_for_position) as they stand BEFORE
# moving them into Scheduling::Signup::Bulk.
#
# Pins WHICH signups get deleted (only matching FUTURE rows for the current year) and that
# a person-slot-remove ActionLog row is written per deletion. Slots are built
# programmatically with explicit begins/begins_year so the time-window filter is exercised
# deterministically against a frozen clock.
#
# Mgmt is the single seam under test; after the refactor it is repointed at
# Scheduling::Signup::Bulk and the file must pass UNCHANGED.
class Scheduling::SignupBulkCharacterizationTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  Mgmt = Scheduling::Management
  Bulk = Scheduling::Signup::Bulk

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Current.reset
    @person = person(:active_ranger)
    Current.person = @person
    @position = positions(:council_manager)
    @other_position = positions(:khaki_supervisor)
    @now = Current.time
    @year = @now.year
  end

  teardown do
    PersonSlot.where(person_id: @person.id).delete_all
  end

  # Build a slot in a given year and sign the person up for it (bypassing capacity).
  def signed_up_slot(position: @position, begins:, year: begins.year)
    s = Slot.create!(
      position: position,
      begins: begins,
      ends: begins + 6.hours,
      max: 50, active: true, timezone: "America/Los_Angeles"
    )
    s.update_columns(begins_year: year)
    PersonSlot.create!(person_id: @person.id, slot_id: s.id)
    s.reload
  end

  def remove_future = Mgmt.remove_future_sign_ups(@person.id, "conversion to bonked")
  def remove_future_for_position(pos_id)
    Mgmt.remove_future_sign_ups_for_position(@person.id, pos_id, "position revoked")
  end

  def removal_log_count
    ActionLog.where(event: "person-slot-remove", target_person_id: @person.id).count
  end

  # ===== remove_future_sign_ups =====

  test "remove_future_sign_ups deletes only this-year FUTURE signups; logs each removal" do
    future = signed_up_slot(begins: Time.zone.local(@year, 8, 25, 10, 0, 0))
    past = signed_up_slot(begins: Time.zone.local(@year, 4, 16, 8, 0, 0)) # < now
    other_year = signed_up_slot(begins: Time.zone.local(@year + 1, 8, 25, 10, 0, 0))

    before = removal_log_count
    remove_future

    assert_not PersonSlot.exists?(person_id: @person.id, slot_id: future.id), "future signup should be removed"
    assert PersonSlot.exists?(person_id: @person.id, slot_id: past.id), "past signup must be untouched"
    assert PersonSlot.exists?(person_id: @person.id, slot_id: other_year.id), "other-year signup must be untouched"

    # One row per removal. This pinned TWO until delete_signup started recording the
    # slot_id itself: the caller loop existed only to write a second, slot-bearing row,
    # so every bulk removal was audited twice -- one row naming the shift and one not.
    # (Reports were not double-counting; they key on slot_id, so the slot-less row was
    # skipped and the removal counted once.)
    assert_equal before + 1, removal_log_count
    assert_equal future.id, ActionLog.where(event: "person-slot-remove",
                                            target_person_id: @person.id).last.data["slot_id"]
  end

  test "remove_future_sign_ups with no future signups deletes nothing and writes no log" do
    past = signed_up_slot(begins: Time.zone.local(@year, 4, 16, 8, 0, 0))
    before = removal_log_count
    remove_future
    assert PersonSlot.exists?(person_id: @person.id, slot_id: past.id)
    assert_equal before, removal_log_count
  end

  # The future window is decided entirely by the present instant, so the SAME August slot
  # is dropped or kept depending only on where the clock sits relative to the shift. The
  # pair is the point: the removal above shows one half, these show both halves of the
  # same boundary. (Ported from signup_clock_test, which drove this with an injected
  # clock; with that parameter gone, travel_to moves the present instead.)
  test "remove_future_sign_ups drops the shift when the clock sits before it" do
    slot = signed_up_slot(begins: Time.zone.local(@year, 8, 25, 10, 0, 0))

    # April 16 -- the August shift is still ahead, so it is in-window.
    travel_to(Time.zone.local(@year, 4, 16, 12, 0, 0)) { remove_future }

    assert_not PersonSlot.exists?(person_id: @person.id, slot_id: slot.id),
               "a shift the clock has not reached yet is in-window and removed"
  end

  test "remove_future_sign_ups keeps the shift when the clock is already past it" do
    slot = signed_up_slot(begins: Time.zone.local(@year, 8, 25, 10, 0, 0))

    # September 1 -- the August shift is behind the clock, so it is out-of-window and
    # survives, though the identical slot is removed from April.
    travel_to(Time.zone.local(@year, 9, 1, 12, 0, 0)) { remove_future }

    assert PersonSlot.exists?(person_id: @person.id, slot_id: slot.id),
           "a shift the clock has already passed is out-of-window and kept"
  end

  # ===== remove_future_sign_ups_for_position =====

  test "remove_future_sign_ups_for_position deletes only this-year future signups for that position" do
    target = signed_up_slot(position: @position, begins: Time.zone.local(@year, 8, 25, 10, 0, 0))
    other_pos = signed_up_slot(position: @other_position, begins: Time.zone.local(@year, 8, 26, 10, 0, 0))
    other_year = signed_up_slot(position: @position, begins: Time.zone.local(@year + 1, 8, 25, 10, 0, 0))

    remove_future_for_position(@position.id)

    assert_not PersonSlot.exists?(person_id: @person.id, slot_id: target.id), "matching future signup removed"
    assert PersonSlot.exists?(person_id: @person.id, slot_id: other_pos.id), "other-position signup untouched"
    assert PersonSlot.exists?(person_id: @person.id, slot_id: other_year.id), "other-year signup untouched"
  end

  # delete_signup logs only on success, and neither bulk method reads the status
  # back, so a removal that rolls back under lock would otherwise leave a bonked
  # person on the schedule with nothing anywhere to say why.
  # delete_signup logs only on success, and the loops do not read the status
  # back, so without this branch a removal that rolls back under lock leaves a
  # bonked person on the schedule with nothing anywhere to say why. Only a race
  # or a lock timeout reaches it through the loop, so the guard is exercised
  # directly rather than by stubbing the store out from under it.
  def log_failed(status) = Bulk.log_failed_removal(@person.id, 4242, "conversion to bonked", status)

  test "a removal that does not succeed is audited, and a successful one is not" do
    log_failed(Scheduling::STATUS_SUCCESS)

    assert_equal 0, ActionLog.where(event: "person-slot-remove-failed").count

    log_failed(Scheduling::STATUS_DB_FAILURE)

    failure = ActionLog.where(event: "person-slot-remove-failed",
                              target_person_id: @person.id).last
    assert_not_nil failure, "the failure is audited"
    assert_equal 4242, failure.data["slot_id"]
    assert_equal Scheduling::STATUS_DB_FAILURE, failure.data["status"]
    # And never as a removal that happened.
    assert_equal 0, ActionLog.where(event: "person-slot-remove",
                                    target_person_id: @person.id).count
  end

  test "remove_future_sign_ups_for_position writes a person-slot-remove log per removal" do
    signed_up_slot(position: @position, begins: Time.zone.local(@year, 8, 25, 10, 0, 0))
    before = removal_log_count
    remove_future_for_position(@position.id)
    # Same single-row audit shape as remove_future_sign_ups.
    assert_equal before + 1, removal_log_count
  end
end
