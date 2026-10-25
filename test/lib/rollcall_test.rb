# frozen_string_literal: true

require "test_helper"

class RollcallTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2031

  setup do
    Rails.cache.clear
    Current.reset

    @now = Time.zone.local(YEAR, 8, 30, 20, 0, 0)
    travel_to @now
    Current.person = person(:active_ranger)

    @ranger = person(:echelon_ranger)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  def make_position(id, title)
    Position.find_by(id: id)&.destroy
    Position.create!(id: id, title: title, type: Position::TYPE_FRONTLINE,
                     no_training_required: true, active: true)
  end

  def make_slot(position, begins:)
    Slot.create!(position_id: position.id, description: "Shift", begins: begins,
                 ends: begins + 6.hours, max: 20, active: true)
  end

  def make_entry(person, position, on_duty:, off_duty: nil)
    Timesheet.create!(person:, position:, on_duty:, off_duty:, additional_notes: "test shift")
  end

  # ------------------------------------------------------------- shift window

  test "shift_groups offers only slots inside the rollcall window" do
    position = make_position(Position::BURN_PERIMETER, "Burn Perimeter")
    inside = make_slot(position, begins: @now + 1.hour)
    too_early = make_slot(position, begins: @now - 5.hours)
    too_late = make_slot(position, begins: @now + 3.hours)

    slot_ids = Rollcall.shift_groups.flat_map { |group| group.members.map(&:id) }

    assert_includes slot_ids, inside.id
    assert_not_includes slot_ids, too_early.id
    assert_not_includes slot_ids, too_late.id
  end

  # SignInBlocker#check_slots only considers active slots, so a cancelled shift
  # left in the picker would be signed against while the timing blocker judged
  # the check-in against a different shift entirely.
  test "shift_groups leaves cancelled shifts out of the picker" do
    position = make_position(9013, "Rollcall Position")
    live = make_slot(position, begins: @now + 1.hour)
    cancelled = make_slot(position, begins: @now + 1.hour)
    cancelled.update!(active: false)

    slot_ids = Rollcall.shift_groups.flat_map { |group| group.members.map(&:id) }

    assert_includes slot_ids, live.id
    assert_not_includes slot_ids, cancelled.id
  end

  test "burn positions come first and the rest are alphabetical" do
    aardvark = make_position(9001, "Aardvark Wrangler")
    zebra = make_position(9002, "Zebra Wrangler")
    sandman = make_position(Position::SANDMAN, "Sandman")
    perimeter = make_position(Position::BURN_PERIMETER, "Burn Perimeter")
    art_car = make_position(Position::ART_CAR_WRANGLER, "Art Car Wrangler")

    [aardvark, zebra, sandman, perimeter, art_car].each do |position|
      make_slot(position, begins: @now + 1.hour)
    end

    titles = Rollcall.shift_groups.map(&:title)

    # Upstream unshifts Sandman, then Burn Perimeter, then Art Car Wrangler
    # onto the front of the list, which lands them in exactly this order.
    assert_equal ["Art Car Wrangler", "Burn Perimeter", "Sandman",
                  "Aardvark Wrangler", "Zebra Wrangler"], titles
  end

  # ------------------------------------------------------------ sign-in roster

  test "the sign-in roster carries each signup's open entry and nothing else" do
    position = make_position(9003, "Rollcall Position")
    other = make_position(9004, "Other Position")
    slot = make_slot(position, begins: @now + 1.hour)
    PersonSlot.create!(person_id: @ranger.id, slot_id: slot.id)
    entry = make_entry(@ranger, other, on_duty: @now - 1.hour)

    row = Rollcall.sign_in_roster(slot).sole

    assert_equal @ranger.id, row.person_id
    assert_equal entry.id, row.entry.id
    assert row.on_duty?
    assert row.elsewhere?(position.id), "out on another position reads as elsewhere"
    assert_not row.elsewhere?(other.id), "out on this position does not"
  end

  test "a closed entry does not make a signup look on duty" do
    position = make_position(9005, "Rollcall Position")
    slot = make_slot(position, begins: @now + 1.hour)
    PersonSlot.create!(person_id: @ranger.id, slot_id: slot.id)
    make_entry(@ranger, position, on_duty: @now - 3.hours, off_duty: @now - 1.hour)

    row = Rollcall.sign_in_roster(slot).sole

    assert_nil row.entry
    assert_not row.on_duty?
  end

  # ----------------------------------------------------------- sign-out roster

  test "the sign-out roster leaves a never-closed entry from a past event alone" do
    position = make_position(9006, "Rollcall Position")
    make_entry(@ranger, position, on_duty: Time.zone.local(YEAR - 2, 8, 30, 20, 0, 0))

    assert_empty Rollcall.sign_out_positions,
                 "a stale entry belongs to Mass Sign-Out, where closing it is deliberate"
  end

  test "the sign-out roster lists this year's open entries under their position" do
    position = make_position(9007, "Rollcall Position")
    entry = make_entry(@ranger, position, on_duty: @now - 1.hour)

    group = Rollcall.sign_out_positions.sole
    assert_equal position.id, group.id

    row = Rollcall.sign_out_roster(position.id).sole
    assert_equal entry.id, row.entry.id
    assert row.on_duty?
  end

  # The picker is drawn before a position is chosen, on a board that can hold
  # four hundred entries on burn night. It must not drag every Ranger's photo
  # along to render a <select>.
  test "the sign-out picker carries no people" do
    position = make_position(9008, "Rollcall Position")
    make_entry(@ranger, position, on_duty: @now - 1.hour)

    assert_empty Rollcall.sign_out_positions.sole.members
  end

  # The schema has no app-domain foreign keys, so an open entry can name a
  # Ranger who no longer exists. Such an entry cannot be signed off at all, and
  # if the picker and the count see it while the roster does not, the position
  # appears with an empty roster over a headline number nothing can drive to
  # zero.
  test "an entry whose Ranger is gone is invisible to the picker, the count and the roster" do
    position = make_position(9012, "Rollcall Position")
    entry = make_entry(@ranger, position, on_duty: @now - 1.hour)
    # A control first: while the Ranger exists, all three see the entry.
    assert_equal 1, Rollcall.sign_out_positions.size
    assert_equal 1, Rollcall.on_duty_count(position.id)
    assert_equal 1, Rollcall.sign_out_roster(position.id).size

    entry.update_columns(person_id: 0)

    assert_empty Rollcall.sign_out_positions
    assert_equal 0, Rollcall.on_duty_count(position.id)
    assert_empty Rollcall.sign_out_roster(position.id)
  end

  test "on_duty_count refuses a blank position rather than counting orphans" do
    assert_equal 0, Rollcall.on_duty_count(nil)
    assert_equal 0, Rollcall.on_duty_count("")
  end

  # ------------------------------------------------------------------ counts

  test "the counts are computed without building a roster" do
    position = make_position(9009, "Rollcall Position")
    other = make_position(9010, "Other Position")
    slot = make_slot(position, begins: @now + 1.hour)
    signed_up = [@ranger, person(:active_ranger), person(:auditor_ranger)]
    signed_up.each { |p| PersonSlot.create!(person_id: p.id, slot_id: slot.id) }

    # One on this shift's position, one out elsewhere, one not out at all.
    make_entry(@ranger, position, on_duty: @now - 1.hour)
    make_entry(person(:active_ranger), other, on_duty: @now - 1.hour)

    assert_equal({ signed_in: 1, total: 3 },
                 Rollcall.sign_in_counts(slot.id, position.id))
    assert_equal 1, Rollcall.on_duty_count(position.id)
    assert_equal 0, Rollcall.on_duty_count(make_position(9011, "Empty").id)
  end
end
