# frozen_string_literal: true

require "test_helper"

class TimesheetSlotRepairTest < ActiveSupport::TestCase
  # A year the timesheet fixtures leave alone -- they carry 2023, 2024, and
  # 2025 entries, which would ride along in every count.
  YEAR = 2021

  setup do
    Current.reset
    @person = person(:active_ranger)
    @other = person(:inactive_ranger)
    @position = positions(:ood_position)
    @other_position = positions(:training_lead)
    Current.person = @person
  end

  teardown { Current.reset }

  def august(day, hour = 12, minute = 0)
    Time.zone.local(YEAR, 8, day, hour, minute, 0)
  end

  def shift(begins, position: @position, description: "Test Shift", hours: 6)
    Slot.create!(position:, begins:, ends: begins + hours.hours,
                 description:, max: 10, active: true)
  end

  def entry(on_duty:, who: @person, position: @position, slot: nil)
    Timesheet.create!(person: who, position:, on_duty:, off_duty: on_duty + 4.hours,
                      slot:, additional_notes: "test entry")
  end

  def sign_up(slot, who: @person)
    PersonSlot.create!(person: who, slot:)
  end

  # --- the matching rule -------------------------------------------------

  test "an entry with no shift is linked to the only match in the window" do
    match = shift(august(20, 18))
    row = entry(on_duty: august(20, 17, 45))
    row.update_column(:slot_id, nil)

    changes = TimesheetSlotRepair.preview(YEAR)

    assert_equal 1, changes.size
    change = changes.first
    assert_equal :add, change.kind
    assert_nil change.old_shift
    assert_equal match.id, change.new_shift.id
    assert_equal TimesheetSlotRepair::ONLY_MATCH, change.reason
  end

  test "a sign-up wins over a shift the ranger did not sign up for" do
    unclaimed = shift(august(20, 17, 30), description: "Unclaimed")
    claimed = shift(august(20, 18), description: "Claimed")
    sign_up(claimed)
    row = entry(on_duty: august(20, 17, 45))
    row.update_column(:slot_id, nil)

    change = TimesheetSlotRepair.preview(YEAR).first

    assert_equal claimed.id, change.new_shift.id, "the sign-up should beat the earlier shift"
    assert_equal TimesheetSlotRepair::SIGNED_UP, change.reason
    assert_not_equal unclaimed.id, change.new_shift.id
  end

  test "two shifts starting together always resolve the same way" do
    first = shift(august(20, 18))
    second = shift(august(20, 18))
    row = entry(on_duty: august(20, 17, 45))
    row.update_column(:slot_id, nil)

    change = TimesheetSlotRepair.preview(YEAR).first

    assert_equal [first.id, second.id].min, change.new_shift.id
  end

  # --- what counts as already correct ------------------------------------

  test "an entry already linked to a matching shift is left alone" do
    match = shift(august(20, 18))
    entry(on_duty: august(20, 17, 45), slot: match)

    assert_empty TimesheetSlotRepair.preview(YEAR)
  end

  # Upstream compared the entry's own start against a window built from that
  # same start, which is always true, so this entry was never repaired.
  test "a shift with the right position but the wrong time is repaired" do
    stale = shift(august(17, 18), description: "Three days early")
    correct = shift(august(20, 18), description: "The real shift")
    row = entry(on_duty: august(20, 17, 45))
    row.update_column(:slot_id, stale.id)

    change = TimesheetSlotRepair.preview(YEAR).first

    assert_equal :change, change.kind
    assert_equal stale.id, change.old_shift.id
    assert_equal correct.id, change.new_shift.id
  end

  test "a shift belonging to another position is repaired" do
    wrong = shift(august(20, 18), position: @other_position, description: "Other position")
    correct = shift(august(20, 18), description: "Right position")
    row = entry(on_duty: august(20, 17, 45))
    row.update_column(:slot_id, wrong.id)

    change = TimesheetSlotRepair.preview(YEAR).first

    assert_equal wrong.id, change.old_shift.id
    assert_equal correct.id, change.new_shift.id
    assert_equal @other_position.title, change.old_shift.position_title,
                 "the old shift shows its own position, not the entry's"
  end

  test "an entry with nothing to point at has its link removed" do
    stale = shift(august(17, 18))
    row = entry(on_duty: august(20, 17, 45))
    row.update_column(:slot_id, stale.id)

    change = TimesheetSlotRepair.preview(YEAR).first

    assert_equal :remove, change.kind
    assert_nil change.new_shift
    assert_nil change.reason
  end

  test "an entry with no shift and no candidate is not reported" do
    entry(on_duty: august(20, 17, 45)).update_column(:slot_id, nil)

    assert_empty TimesheetSlotRepair.preview(YEAR)
  end

  test "clearing a stale link is reported as a success, not an error" do
    stale = shift(august(17, 18))
    row = entry(on_duty: august(20, 17, 45))
    row.update_column(:slot_id, stale.id)

    results, = TimesheetSlotRepair.apply(YEAR, [row.id.to_s])

    assert_nil results.first.error
    assert_equal "no longer linked to a shift", results.first.message
    assert_nil row.reload.slot_id
  end

  # --- the window --------------------------------------------------------

  test "a shift just inside the window matches and one just outside does not" do
    inside = shift(august(20, 12) + TimesheetSlotRepair::MATCH_WINDOW)
    row = entry(on_duty: august(20, 12))
    row.update_column(:slot_id, nil)

    assert_equal inside.id, TimesheetSlotRepair.preview(YEAR).first.new_shift.id

    inside.update!(begins: august(20, 12) + TimesheetSlotRepair::MATCH_WINDOW + 1.minute,
                   ends: august(21, 12))

    assert_empty TimesheetSlotRepair.preview(YEAR)
  end

  # The linked shift and the search for a new one must measure the window the
  # same way, or a shift sitting exactly on the edge is dropped and re-found.
  test "a shift exactly on the edge of the window is left alone" do
    edge = shift(august(20, 12) - TimesheetSlotRepair::MATCH_WINDOW)
    entry(on_duty: august(20, 12), slot: edge)

    assert_empty TimesheetSlotRepair.preview(YEAR)
  end

  test "the window reaches equally far on both sides" do
    early = shift(august(20, 12) - TimesheetSlotRepair::MATCH_WINDOW)
    row = entry(on_duty: august(20, 12))
    row.update_column(:slot_id, nil)

    assert_equal early.id, TimesheetSlotRepair.preview(YEAR).first.new_shift.id
  end

  # --- ordering and scope ------------------------------------------------

  test "changes are sorted by callsign regardless of case" do
    shift(august(20, 18))
    @person.update_column(:callsign, "zebra")
    @other.update_column(:callsign, "Apple")
    entry(on_duty: august(20, 17, 45)).update_column(:slot_id, nil)
    entry(on_duty: august(20, 17, 45), who: @other).update_column(:slot_id, nil)

    assert_equal %w[Apple zebra], TimesheetSlotRepair.preview(YEAR).map(&:callsign)
  end

  test "another year's entries are not touched" do
    shift(august(20, 18))
    entry(on_duty: august(20, 17, 45)).update_column(:slot_id, nil)

    assert_empty TimesheetSlotRepair.preview(YEAR + 1)
  end

  # --- applying ----------------------------------------------------------

  test "applying writes only the selected entries" do
    shift(august(20, 18))
    keep = entry(on_duty: august(20, 17, 45))
    keep.update_column(:slot_id, nil)
    skip = entry(on_duty: august(20, 17, 50), who: @other)
    skip.update_column(:slot_id, nil)

    results, skipped = TimesheetSlotRepair.apply(YEAR, [keep.id.to_s])

    assert_equal 1, results.size
    assert_equal 0, skipped
    assert_not_nil keep.reload.slot_id
    assert_nil skip.reload.slot_id
  end

  test "an entry that no longer needs repairing is counted as skipped" do
    match = shift(august(20, 18))
    row = entry(on_duty: august(20, 17, 45), slot: match)

    results, skipped = TimesheetSlotRepair.apply(YEAR, [row.id.to_s])

    assert_empty results
    assert_equal 1, skipped
  end

  test "applying records both log rows" do
    match = shift(august(20, 18), description: "Swing Shift")
    row = entry(on_duty: august(20, 17, 45))
    row.update_column(:slot_id, nil)

    assert_difference ["TimesheetLog.count", "ActionLog.count"], 1 do
      TimesheetSlotRepair.apply(YEAR, [row.id.to_s])
    end

    log = TimesheetLog.where(timesheet_id: row.id).order(:id).last
    assert_equal TimesheetLog::UPDATE, log.action
    assert_equal [nil, match.id], log.data["slot_id"]
    # String keys, as every other timesheet audit writer uses: decode_data
    # reads them, and the JSON round trip is not the only way a log is read.
    assert_equal ["slot_id"], TimesheetLog.where(timesheet_id: row.id)
                                          .order(:id).last.data.keys

    action = ActionLog.order(:id).last
    assert_equal "timesheet-update", action.event
    assert_equal TimesheetSlotRepair::AUDIT_REASON, action.message
    assert_equal row.person_id, action.target_person_id
  end

  test "the timesheet log shows the shift descriptions it moved between" do
    match = shift(august(20, 18), description: "Swing Shift")
    row = entry(on_duty: august(20, 17, 45))
    row.update_column(:slot_id, nil)
    TimesheetSlotRepair.apply(YEAR, [row.id.to_s])

    decoded = TimesheetLog.where(timesheet_id: row.id).order(:id).last.decode_data

    assert_nil decoded["slot_id"][0]
    assert_equal "Swing Shift", decoded["slot_id"][1]["description"]
  end

  test "applying leaves the hours and the position alone" do
    shift(august(20, 18))
    row = entry(on_duty: august(20, 17, 45))
    row.update_column(:slot_id, nil)
    before = row.reload.attributes.except("slot_id", "updated_at")

    TimesheetSlotRepair.apply(YEAR, [row.id.to_s])

    assert_equal before, row.reload.attributes.except("slot_id", "updated_at")
  end

  test "scan reports the entries it looked at alongside the changes" do
    shift(august(20, 18))
    entry(on_duty: august(20, 17, 45)).update_column(:slot_id, nil)
    entry(on_duty: august(21, 17, 45), who: @other)

    scanned, changes = TimesheetSlotRepair.scan(YEAR)

    assert_equal 2, scanned
    assert_equal 1, changes.size
  end

  test "applying nothing writes nothing" do
    shift(august(20, 18))
    entry(on_duty: august(20, 17, 45)).update_column(:slot_id, nil)

    assert_no_difference "TimesheetLog.count" do
      results, skipped = TimesheetSlotRepair.apply(YEAR, [])
      assert_empty results
      assert_equal 0, skipped
    end
  end
end
