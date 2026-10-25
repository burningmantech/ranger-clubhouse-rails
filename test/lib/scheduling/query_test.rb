# frozen_string_literal: true

require "test_helper"

class Scheduling::QueryTest < ActiveSupport::TestCase
  setup do
    @person = person(:active_ranger)
    @year = Current.year - 1

    # Use two fixture positions already granted to active_ranger via person_position fixtures
    @position_a = positions(:council_manager)
    @position_b = positions(:khaki_supervisor)

    # A third position that the person does NOT hold
    @unheld_position = positions(:ood_position)
  end

  # --- position_id overlap detection ---

  test "position_id mode flags overlapping slot from another held position" do
    # Person is signed up for a slot in position_b that overlaps with a slot in position_a
    slot_a = create_slot(@position_a, hour: 10, duration: 6)
    slot_b = create_slot(@position_b, hour: 12, duration: 4) # overlaps slot_a (10-16 vs 12-16)

    PersonSlot.create!(person: @person, slot: slot_b)

    slots, _positions = Scheduling::Query.find_for_query(@person.id, @year, position_id: @position_a.id)

    entry_a = slots.find { |s| s.slot.id == slot_a.id }
    assert entry_a, "Should return the slot in the selected position"
    assert entry_a.is_overlapping, "Slot should be flagged as overlapping"
    assert entry_a.overlapping_slots.present?, "Should have overlapping_slots populated"

    conflict = entry_a.overlapping_slots.first
    assert_equal slot_b.id, conflict.slot.id
    assert_equal @position_b.id, conflict.position.id
  end

  test "position_id mode does not flag conflicts from unheld positions" do
    # Person does NOT hold unheld_position - signup in unheld_position should not appear as conflict
    slot_a = create_slot(@position_a, hour: 10, duration: 6)
    slot_unheld = create_slot(@unheld_position, hour: 12, duration: 4)

    PersonSlot.create!(person: @person, slot: slot_unheld)

    slots, _positions = Scheduling::Query.find_for_query(@person.id, @year, position_id: @position_a.id)

    entry_a = slots.find { |s| s.slot.id == slot_a.id }
    assert entry_a, "Should return the slot in the selected position"
    assert_not entry_a.is_overlapping, "Slot should NOT be flagged as overlapping (conflict from unheld position)"
    assert_nil entry_a.overlapping_slots
  end

  test "position_id mode detects same-position overlaps among signed-up entries" do
    # Two overlapping slots in the same position that the person is signed up for
    # should still be flagged as overlapping (same-position overlap detection)
    slot_a1 = create_slot(@position_a, hour: 10, duration: 6)
    slot_a2 = create_slot(@position_a, hour: 12, duration: 4)

    PersonSlot.create!(person: @person, slot: slot_a1)
    PersonSlot.create!(person: @person, slot: slot_a2)

    slots, _positions = Scheduling::Query.find_for_query(@person.id, @year, position_id: @position_a.id)

    entry_a1 = slots.find { |s| s.slot.id == slot_a1.id }
    entry_a2 = slots.find { |s| s.slot.id == slot_a2.id }

    assert entry_a1.is_overlapping, "slot_a1 should be flagged as overlapping"
    assert entry_a2.is_overlapping, "slot_a2 should be flagged as overlapping"
  end

  test "position_id mode does not flag non-signed-up same-position slots as overlapping" do
    # Two overlapping slots in the same position but NOT signed up for
    # should not be flagged as overlapping
    create_slot(@position_a, hour: 10, duration: 6)
    create_slot(@position_a, hour: 12, duration: 4)

    slots, _positions = Scheduling::Query.find_for_query(@person.id, @year, position_id: @position_a.id)

    slots.each do |entry|
      assert_not entry.is_overlapping, "Non-signed-up slots should not be flagged as overlapping"
    end
  end

  test "position_id mode evaluates all returned slots for overlaps" do
    # Create multiple selected-position slots; only one should overlap with the signup
    slot_a1 = create_slot(@position_a, hour: 8, duration: 2)  # 8-10, no overlap
    slot_a2 = create_slot(@position_a, hour: 12, duration: 4) # 12-16, overlaps slot_b
    slot_a3 = create_slot(@position_a, hour: 20, duration: 3) # 20-23, no overlap

    slot_b = create_slot(@position_b, hour: 14, duration: 4) # 14-18, overlaps slot_a2
    PersonSlot.create!(person: @person, slot: slot_b)

    slots, _positions = Scheduling::Query.find_for_query(@person.id, @year, position_id: @position_a.id)

    entry_a1 = slots.find { |s| s.slot.id == slot_a1.id }
    entry_a2 = slots.find { |s| s.slot.id == slot_a2.id }
    entry_a3 = slots.find { |s| s.slot.id == slot_a3.id }

    assert_not entry_a1.is_overlapping, "slot_a1 should not overlap"
    assert entry_a2.is_overlapping, "slot_a2 should overlap with slot_b"
    assert entry_a2.overlapping_slots.present?
    assert_not entry_a3.is_overlapping, "slot_a3 should not overlap"
  end

  test "position_id mode sets sign_ups count from signups in selected position" do
    slot_a = create_slot(@position_a, hour: 10, duration: 6)
    PersonSlot.create!(person: @person, slot: slot_a)

    _slots, positions = Scheduling::Query.find_for_query(@person.id, @year, position_id: @position_a.id)

    pos = positions.find { |p| p.id == @position_a.id }
    assert_equal 1, pos.sign_ups
  end

  # --- Regression: non-position_id (only_signups) overlap behavior ---

  test "only_signups mode detects overlapping sign-ups" do
    slot_a = create_slot(@position_a, hour: 10, duration: 6)
    slot_b = create_slot(@position_b, hour: 12, duration: 4)

    PersonSlot.create!(person: @person, slot: slot_a)
    PersonSlot.create!(person: @person, slot: slot_b)

    slots, _positions = Scheduling::Query.find_for_query(@person.id, @year, only_signups: true)

    entry_a = slots.find { |s| s.slot.id == slot_a.id }
    entry_b = slots.find { |s| s.slot.id == slot_b.id }

    assert entry_a.is_overlapping, "slot_a should be overlapping"
    assert entry_b.is_overlapping, "slot_b should be overlapping"
  end

  # An ended sign-up has no entry in remaining mode, so the credit computation
  # must run over the entries' own rows: matched by index against the full row
  # list, the first ended row shifted every credit and the last store row was nil.
  test "remaining mode drops ended sign-ups and still credits the ones ahead" do
    ended = create_slot(@position_a, hour: 8, duration: 2)
    ahead = create_slot(@position_b, hour: 14, duration: 4)
    PersonSlot.create!(person: @person, slot: ended)
    PersonSlot.create!(person: @person, slot: ahead)
    PositionCredit.create!(position: @position_b, credits_per_hour: 2.0,
                           start_time: ahead.begins - 1.day, end_time: ahead.ends + 1.day, description: "test")

    travel_to Time.zone.local(@year, 8, 25, 12) do
      slots, _positions = Scheduling::Query.find_for_query(@person.id, @year, only_signups: true, remaining: true)

      assert_equal [ahead.id], slots.map { |s| s.slot.id }
      assert_in_delta 8.0, slots.first.credits, 0.01
    end
  end

  # The summary's remaining mode counts a shift under way from now, comparing the
  # slot's unix begins_time against the clock -- as an Integer, or it raises.
  test "the remaining schedule summary counts a shift under way from now" do
    EventDate.create!(event_start: Time.zone.local(@year, 8, 24), event_end: Time.zone.local(@year, 9, 1),
                      pre_event_start: Time.zone.local(@year, 8, 10), pre_event_slot_start: Time.zone.local(@year, 8, 10),
                      pre_event_slot_end: Time.zone.local(@year, 8, 24), post_event_end: Time.zone.local(@year, 9, 10))
    under_way = create_slot(@position_a, hour: 10, duration: 6)
    PersonSlot.create!(person: @person, slot: under_way)

    travel_to Time.zone.local(@year, 8, 25, 12) do
      summary = Scheduling::Summaries.schedule_summary_for_person_year(@person.id, @year, remaining: true)

      assert_equal 4.hours.to_i, summary.event_duration
    end
  end

  test "non-position_id mode propagates overlapping_slots to available slots" do
    # When browsing all positions (no position_id), overlaps from sign-ups should propagate
    slot_a = create_slot(@position_a, hour: 10, duration: 6)
    slot_b = create_slot(@position_b, hour: 12, duration: 4)

    PersonSlot.create!(person: @person, slot: slot_a)
    PersonSlot.create!(person: @person, slot: slot_b)

    slots, _positions = Scheduling::Query.find_for_query(@person.id, @year)

    entry_a = slots.find { |s| s.slot.id == slot_a.id }
    entry_b = slots.find { |s| s.slot.id == slot_b.id }

    assert entry_a.overlapping_slots.present?, "slot_a should have overlapping_slots"
    assert entry_b.overlapping_slots.present?, "slot_b should have overlapping_slots"
  end

  # --- partition_by_time: intentional cutoff divergence ---

  # Lightweight doubles: partition_by_time only reads entry.slot.has_started /
  # entry.slot.has_ended, so we avoid DB/Current.time and pin the predicates directly.
  SlotDouble = Struct.new(:has_started, :has_ended)
  EntryDouble = Struct.new(:slot)

  def build_entry(started:, ended:)
    EntryDouble.new(SlotDouble.new(started, ended))
  end

  test "partition_by_time :start_time puts in-progress slot in past" do
    not_started = build_entry(started: false, ended: false)
    in_progress = build_entry(started: true, ended: false)
    ended = build_entry(started: true, ended: true)

    upcoming, past = Scheduling::Query.partition_by_time([not_started, in_progress, ended], cutoff: :start_time)

    assert_equal [not_started], upcoming
    assert_equal [in_progress, ended], past
  end

  test "partition_by_time :end_time puts in-progress slot in upcoming" do
    not_started = build_entry(started: false, ended: false)
    in_progress = build_entry(started: true, ended: false)
    ended = build_entry(started: true, ended: true)

    upcoming, past = Scheduling::Query.partition_by_time([not_started, in_progress, ended], cutoff: :end_time)

    assert_equal [not_started, in_progress], upcoming
    assert_equal [ended], past
  end

  test "partition_by_time preserves input order within each bucket" do
    e1 = build_entry(started: false, ended: false)
    e2 = build_entry(started: true, ended: true)
    e3 = build_entry(started: false, ended: false)
    e4 = build_entry(started: true, ended: true)
    entries = [e1, e2, e3, e4]

    upcoming, past = Scheduling::Query.partition_by_time(entries, cutoff: :start_time)

    assert_equal [e1, e3], upcoming, "upcoming keeps input order"
    assert_equal [e2, e4], past, "past keeps input order"
  end

  test "partition_by_time preserves total count for both cutoffs" do
    entries = [
      build_entry(started: false, ended: false),
      build_entry(started: true, ended: false),
      build_entry(started: true, ended: true)
    ]

    [:start_time, :end_time].each do |cutoff|
      upcoming, past = Scheduling::Query.partition_by_time(entries, cutoff: cutoff)
      assert_equal entries.size, upcoming.size + past.size, "no entry dropped or duplicated for #{cutoff}"
    end
  end

  test "partition_by_time raises ArgumentError for unknown cutoff" do
    assert_raises(ArgumentError) do
      Scheduling::Query.partition_by_time([], cutoff: :bogus)
    end
  end

  # Regression: build_shift_info lives on Scheduling::Summaries; the unqualified
  # call here raised NoMethodError the first time a sign-up was within range.
  test "retrieve_starting_slots_for_person builds imminent and upcoming shift info" do
    now = Current.time
    imminent_slot = Slot.create!(position: @position_a, begins: now + 10.minutes,
                                 ends: now + 6.hours, max: 10, active: true,
                                 timezone: "America/Los_Angeles")
    upcoming_slot = Slot.create!(position: @position_b, begins: now + 3.hours,
                                 ends: now + 9.hours, max: 10, active: true,
                                 timezone: "America/Los_Angeles")
    PersonSlot.create!(person: @person, slot: imminent_slot)
    PersonSlot.create!(person: @person, slot: upcoming_slot)

    result = Scheduling::Query.retrieve_starting_slots_for_person(@person.id)

    imminent = result.imminent.find { |shift| shift.slot_id == imminent_slot.id }
    assert imminent, "the shift starting within the locate window should be imminent"
    assert_equal @position_a.id, imminent.position_id
    assert_equal @position_a.title, imminent.position_title

    assert result.upcoming.any? { |shift| shift.slot_id == upcoming_slot.id },
           "the later shift should be listed as upcoming"
  end

  private

  def create_slot(position, hour:, duration:)
    base = Time.zone.local(@year, 8, 25, hour, 0, 0)
    Slot.create!(
      position: position,
      begins: base,
      ends: base + duration.hours,
      max: 10,
      active: true,
      timezone: "America/Los_Angeles"
    )
  end
end
