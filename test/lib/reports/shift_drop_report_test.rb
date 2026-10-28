# frozen_string_literal: true

require "test_helper"

# The two things the controller test cannot reach cleanly: the notice is exact
# rather than pre-rounded, and a removal outlives the person it names.
class ShiftDropReportTest < ActiveSupport::TestCase
  include TrainingSlotTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2031

  setup do
    @now = Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    travel_to @now
    Current.reset

    @position = positions(:ood_position)
    @slot = create_slot(@position, begins: @now + 20.hours, ends: @now + 26.hours)
    @person = person(:active_ranger)
  end

  teardown do
    travel_back
    Current.reset
  end

  def log_drop(person_id, at:)
    ActionLog.create!(event: "person-slot-remove", message: "removed",
                      target_person_id: person_id, data: { "slot_id" => @slot.id },
                      created_at: at)
  end

  def only_drop(hours: ShiftDropReport::DEFAULT_HOURS)
    ShiftDropReport.position(year: YEAR, hours:, position: @position)
                   .slot_drops.first.drops.first
  end

  # Rounded on the way in, 47 minutes of notice came back out of the page as
  # "48 min" -- 0.783 hours had already become 0.8.
  test "the notice is kept exact and rounded only for the export" do
    log_drop(@person.id, at: @slot.begins - 47.minutes)

    drop = only_drop

    assert_equal 47 * 60, drop.seconds_before.to_i
    assert_in_delta 0.8, drop.hours_before, 0.001
  end

  test "a drop is urgent by its real distance from the start, not its rounding" do
    log_drop(@person.id, at: @slot.begins - ShiftDropReport::URGENT_HOURS.hours)

    assert_predicate only_drop, :urgent?

    ActionLog.delete_all
    log_drop(@person.id, at: @slot.begins - (ShiftDropReport::URGENT_HOURS.hours + 1.minute))

    assert_not_predicate only_drop, :urgent?
  end

  # The Laravel-shared schema carries no foreign keys, so the person named by a
  # removal really can be gone. The placeholder matches the one
  # LinkHelper#person_display_name renders, so the row and its sort key agree.
  test "a removal naming a person who no longer exists still reports" do
    log_drop(0, at: @slot.begins - 1.hour)

    drop = only_drop

    assert_nil drop.person
    assert_equal "Deleted #0", drop.callsign
  end

  # A shift's begins is the wall clock of its own zone. New York's 09:00 is
  # 06:00 here, so a removal logged at 05:00 here left an hour, not four.
  test "a shift in another zone measures the notice on its own clock" do
    new_york = create_slot(@position, begins: Time.zone.local(YEAR, 8, 27, 9, 0, 0), timezone: "America/New_York")
    ActionLog.create!(event: "person-slot-remove", message: "removed", target_person_id: @person.id,
                      data: { "slot_id" => new_york.id }, created_at: Time.zone.local(YEAR, 8, 27, 5, 0, 0))

    drop = ShiftDropReport.position(year: YEAR, position: @position).slot_drops.sole.drops.sole

    assert_equal 60 * 60, drop.seconds_before.to_i
    assert drop.urgent?
  end

  # January, when Pacific runs an hour behind: 07:30 here is 06:30 in Los
  # Angeles, half an hour before a 07:00 shift rather than half an hour after.
  test "a Pacific shift in winter counts a removal from its own clock" do
    january = create_slot(@position, begins: Time.zone.local(YEAR, 1, 15, 7, 0, 0))
    ActionLog.create!(event: "person-slot-remove", message: "removed", target_person_id: @person.id,
                      data: { "slot_id" => january.id }, created_at: Time.zone.local(YEAR, 1, 15, 7, 30, 0))

    drop = ShiftDropReport.position(year: YEAR, position: @position).slot_drops.sole.drops.sole

    assert_equal 30 * 60, drop.seconds_before.to_i
  end

  # Upstream clamps created_at to the report year, which loses the December
  # removals of an early-January shift. The window is bounded by the shift.
  test "a window reaching into the previous year is not clipped" do
    january = create_slot(@position, begins: Time.zone.local(YEAR, 1, 1, 6, 0, 0),
                                     ends: Time.zone.local(YEAR, 1, 1, 12, 0, 0))
    ActionLog.create!(event: "person-slot-remove", message: "removed",
                      target_person_id: @person.id, data: { "slot_id" => january.id },
                      created_at: january.begins - 8.hours)

    detail = ShiftDropReport.position(year: YEAR, hours: 12, position: @position)

    assert_equal 1, detail.drop_count
    assert_equal january.id, detail.slot_drops.first.slot.id
  end
end
