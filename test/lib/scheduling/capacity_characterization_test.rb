# frozen_string_literal: true

require "test_helper"

# Characterization of the parent/child/trainer slot CAPACITY math as it stands BEFORE
# extracting Scheduling::SlotCapacity. Pins:
#   - Management#compute_signups   (the +1 WRITE-PREVIEW: is the seat available, did it just fill)
#   - Slot.retrieve_sign_ups       (the no-+1 DISPLAY rollup, per-slot)
#   - Query#adjust_parent_child_signups (the no-+1 DISPLAY rollup, batch over rows)
# so repointing all three at one SlotCapacity is provably behaviour-preserving.
class Scheduling::CapacityCharacterizationTest < ActiveSupport::TestCase
  Mgmt = Scheduling::Management

  setup do
    @year = Current.year
    @position = positions(:council_manager)
  end

  # Build a slot with explicit counts/links (bypassing callbacks via update_columns).
  def slot(max:, signed_up: 0, child_of: nil, trainer: nil)
    s = Slot.create!(
      position: @position,
      begins: Time.zone.local(@year, 8, 25, 10, 0, 0),
      ends: Time.zone.local(@year, 8, 25, 16, 0, 0),
      max: max, active: true, timezone: "America/Los_Angeles"
    )
    s.update_columns(signed_up: signed_up, parent_signup_slot_id: child_of&.id, trainer_slot_id: trainer&.id)
    s.reload
  end

  def preview(slot, force: false)
    Mgmt.send(:compute_signups, slot, Mgmt::SignupResult.new, force)
  end

  # ===== WRITE-PREVIEW (compute_signups, +1) =====

  test "plain slot below max: success, not full, combined_max = max" do
    r = preview(slot(max: 10, signed_up: 5))
    assert_equal Scheduling::STATUS_SUCCESS, r.status
    assert_not r.is_full
    assert_equal 10, r.combined_max
  end

  test "plain slot at max: FULL unless forced; force succeeds but stays full" do
    full = slot(max: 10, signed_up: 10)
    r = preview(full)
    assert_equal Scheduling::STATUS_FULL, r.status
    assert r.is_full
    assert_equal 10, r.combined_max

    forced = preview(slot(max: 10, signed_up: 10), force: true)
    assert_equal Scheduling::STATUS_SUCCESS, forced.status
    assert forced.is_full
  end

  test "trainer slot multiplies effective max by trainer signups" do
    trainer = slot(max: 99, signed_up: 3)
    s = slot(max: 2, signed_up: 5, trainer: trainer) # effective max 2*3 = 6
    r = preview(s)
    assert_equal Scheduling::STATUS_SUCCESS, r.status
    assert_equal 6, r.combined_max
    assert_not r.is_full

    s_full = slot(max: 2, signed_up: 6, trainer: trainer)
    assert_equal Scheduling::STATUS_FULL, preview(s_full).status
  end

  test "child slot (has parent): blocked when combined reaches parent max" do
    parent = slot(max: 10, signed_up: 8)
    child = slot(max: 10, signed_up: 2, child_of: parent) # combined 10 >= parent.max
    r = preview(child)
    assert_equal Scheduling::STATUS_FULL, r.status
    assert r.is_full
    assert_equal 10, r.combined_max
    assert_equal parent.id, r.linked_slots.first.slot.id
    assert_equal 10, r.linked_slots.first.signed_up # combined
  end

  test "child slot (has parent): room left, reports adjusted parent rollup" do
    parent = slot(max: 10, signed_up: 3)
    child = slot(max: 10, signed_up: 2, child_of: parent) # combined 5
    r = preview(child)
    assert_equal Scheduling::STATUS_SUCCESS, r.status
    assert_not r.is_full
    link = r.linked_slots.first
    assert_equal parent.id, link.slot.id
    assert_equal 6, link.signed_up # adjusted_combined = combined(5) + 1
    assert_equal 10, link.max
    assert_not r.linked_slots_became_full
  end

  test "child slot: linked_slots_became_full true when this seat fills the parent" do
    parent = slot(max: 10, signed_up: 5)
    child = slot(max: 10, signed_up: 4, child_of: parent) # combined 9; (9+1)==10
    r = preview(child)
    assert r.linked_slots_became_full
    assert r.is_full # adjusted_combined 10 >= parent.max
  end

  test "parent slot (has child): room left, folds child count for display" do
    parent = slot(max: 10, signed_up: 2)
    _child = slot(max: 10, signed_up: 3, child_of: parent)
    r = preview(parent.reload)
    assert_equal Scheduling::STATUS_SUCCESS, r.status
    assert_not r.is_full
    link = r.linked_slots.first
    assert_equal 3, link.signed_up # child count, room left
    assert_not r.linked_slots_became_full
  end

  test "parent slot (has child): full when own seat fills own max via combined" do
    parent = slot(max: 10, signed_up: 4)
    _child = slot(max: 10, signed_up: 5, child_of: parent) # combined 9; final_sign_ups 10 >= max
    r = preview(parent.reload)
    assert r.is_full
    assert r.linked_slots_became_full # (9+1)==10
    assert_equal 10, r.linked_slots.first.signed_up # child clamped to child.max
  end

  test "parent slot (has child): blocked when combined already at max" do
    parent = slot(max: 10, signed_up: 6)
    _child = slot(max: 10, signed_up: 4, child_of: parent) # combined 10 >= max
    r = preview(parent.reload)
    assert_equal Scheduling::STATUS_FULL, r.status
    assert r.is_full
    assert_equal 10, r.linked_slots.first.signed_up # child.max
  end

  # ===== TRAINER-MULTIPLIER KERNEL (SlotCapacity#effective_max) =====
  # The kernel owns the WHOLE rule: the guard (does a trainer slot exist?) plus the
  # multiply. Callers supply only the freshly-obtained trainer count via their own
  # freshness contract; all three contracts are exercised below.

  test "effective_max: no trainer slot leaves base max untouched (count ignored)" do
    plain = slot(max: 2, signed_up: 0)
    # No trainer slot: base unchanged, regardless of any count a caller might pass.
    assert_equal 2, Scheduling::SlotCapacity.new(plain).effective_max
    assert_equal 2, Scheduling::SlotCapacity.new(plain).effective_max(trainer_signed_up: 99)
  end

  test "effective_max: trainer slot multiplies base by the supplied fresh count" do
    trainer = slot(max: 99, signed_up: 3)
    s = slot(max: 2, signed_up: 0, trainer: trainer)
    # Write-path / query-path contract: caller supplies the freshly-obtained count.
    assert_equal 6, Scheduling::SlotCapacity.new(s).effective_max(trainer_signed_up: 3)
    # 0 trainers zeroes the capacity (distinct from "no trainer slot").
    assert_equal 0, Scheduling::SlotCapacity.new(s).effective_max(trainer_signed_up: 0)
  end

  test "effective_max: in-memory contract reads the count off the loaded association" do
    trainer = slot(max: 99, signed_up: 3)
    s = slot(max: 2, signed_up: 0, trainer: trainer)
    # Display in-memory contract: caller omits the count; kernel reads :trainer_slot.
    assert_equal 6, Scheduling::SlotCapacity.new(s.reload).effective_max
  end

  # ===== DISPLAY ROLLUP (Slot.retrieve_sign_ups, no +1) =====

  test "display: child slot folds into parent count, capped at parent max" do
    parent = slot(max: 10, signed_up: 7)
    child = slot(max: 10, signed_up: 2, child_of: parent)
    res = Slot.retrieve_sign_ups(child)
    # combined 9 < parent.max -> parent_count = 7 + 2 = 9
    assert_equal 9, res.parent.signed_up
    assert_equal 10, res.combined_max
  end

  test "display: child slot clamps both to max when combined reaches parent max" do
    parent = slot(max: 10, signed_up: 8)
    child = slot(max: 10, signed_up: 5, child_of: parent) # combined 13 >= parent.max
    res = Slot.retrieve_sign_ups(child)
    assert_equal 10, res.parent.signed_up # parent.max
    assert_equal child.max, res.signed_up # clamped to child.max
  end

  test "display: parent slot folds child count, trainer multiplier on plain" do
    parent = slot(max: 10, signed_up: 4)
    child = slot(max: 10, signed_up: 3, child_of: parent)
    res = Slot.retrieve_sign_ups(parent.reload)
    assert_equal child.id, res.child.slot_id
    # combined 7 < max -> signed_up rolls to 4 + 3 = 7
    assert_equal 7, res.signed_up
  end

  # ===== DISPLAY ROLLUP (Query#adjust_parent_child_signups, batch, no +1) =====

  test "adjust_parent_child_signups: folds child into parent across rows" do
    parent = slot(max: 10, signed_up: 4)
    child = slot(max: 10, signed_up: 3, child_of: parent)
    rows = [parent.reload, child.reload]
    Scheduling::Query.adjust_parent_child_signups(rows)
    assert_equal 7, rows.first.signed_up # 4 + 3
  end

  test "adjust_parent_child_signups: clamps both to max when combined reaches parent max" do
    parent = slot(max: 10, signed_up: 8)
    child = slot(max: 10, signed_up: 5, child_of: parent)
    rows = [parent.reload, child.reload]
    Scheduling::Query.adjust_parent_child_signups(rows)
    assert_equal 10, rows.first.signed_up
    assert_equal child.max, rows.last.signed_up
  end
end
