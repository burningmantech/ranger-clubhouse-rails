# frozen_string_literal: true

require "test_helper"

# Training::CapacityReport: the fill math, the status-at-session-time buckets,
# the roster-scoped pass counts, the landing-rule trainer matching, and the
# ended-sessions-only pass totals.
class Training::CapacityReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include TrainingSlotTestHelper

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)
    Current.reset

    @training = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                 type: Position::TYPE_TRAINING, active: true)
    @trainer_position = Position.create!(id: Position::GREEN_DOT_TRAINER, title: "Green Dot Trainer",
                                         type: Position::TYPE_TRAINING, active: true)
  end

  teardown do
    Current.reset
    travel_back
  end

  test "signups bucket by their status at session time" do
    slot = create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0))

    # Prospective when the session ran, converted to active afterwards -- the
    # session-time status must win.
    converted = sign_up(person(:active_ranger), slot)
    record_status(converted, "prospective", at: Time.zone.local(YEAR, 1, 5))
    record_status(converted, "active", at: Time.zone.local(YEAR, 7, 1))

    auditing = sign_up(person(:auditor_ranger), slot)
    record_status(auditing, "auditor", at: Time.zone.local(YEAR, 1, 5))

    veteran = sign_up(person(:retired_ranger), slot)
    record_status(veteran, "active", at: Time.zone.local(YEAR - 4, 1, 5))

    # No status history at all falls through to the Returning bucket.
    sign_up(person(:echelon_ranger), slot)

    row = Training::CapacityReport.execute(@training, YEAR).rows.first

    assert_equal 4, row.signed_up
    assert_equal 1, row.pnv_count
    assert_equal 1, row.auditor_count
    assert_equal 2, row.veteran_count
  end

  test "filled percentage rounds, zeroes on zero seats, and can exceed 100" do
    unlimited = create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), max: 0)
    sign_up(person(:active_ranger), unlimited)

    packed = create_slot(@training, begins: Time.zone.local(YEAR, 6, 8, 9, 0, 0), max: 2)
    sign_up(person(:auditor_ranger), packed)
    sign_up(person(:retired_ranger), packed)
    sign_up(person(:echelon_ranger), packed)

    partial = create_slot(@training, begins: Time.zone.local(YEAR, 6, 15, 9, 0, 0), max: 3)
    sign_up(person(:alpha_ranger), partial)
    sign_up(person(:prospective_ranger), partial)

    rows = Training::CapacityReport.execute(@training, YEAR).rows

    assert_equal [0, 150, 67], rows.map(&:filled)
  end

  test "zero-signup sessions report zeros and skip trainer matching" do
    slot = create_slot(@training, begins: Time.zone.local(YEAR, 9, 1, 9, 0, 0))
    trainer_slot = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 9, 1, 8, 30, 0))
    sign_up(person(:active_ranger), trainer_slot)

    report = Training::CapacityReport.execute(@training, YEAR)
    row = report.rows.first

    assert_equal 0, row.signed_up
    assert_equal 0, row.filled
    assert_equal 0, row.pnv_count
    assert_equal 0, row.veteran_count
    assert_equal 0, row.auditor_count
    assert_equal 0, row.trainer_count
    assert_equal 0, report.unique_trainers
  end

  test "passed counts only people still on the roster" do
    slot = create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0))
    passed = sign_up(person(:active_ranger), slot)
    sign_up(person(:retired_ranger), slot)
    TraineeStatus.create!(person_id: passed.id, slot_id: slot.id, status: TraineeStatus::STATUS_PASSED)
    # Scored, but later dropped from the roster -- must not count.
    TraineeStatus.create!(person_id: person(:echelon_ranger).id, slot_id: slot.id, status: TraineeStatus::STATUS_PASSED)

    row = Training::CapacityReport.execute(@training, YEAR).rows.first

    assert_equal 1, row.passed
    assert_equal 1, row.not_passed
  end

  test "trainer counts use the landing match rule and dedupe across sessions" do
    first = create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: "Bright Eyes")
    second = create_slot(@training, begins: Time.zone.local(YEAR, 6, 8, 9, 0, 0), description: "Dim Eyes")
    sign_up(person(:alpha_ranger), first)
    sign_up(person(:prospective_ranger), second)

    trainer = person(:active_ranger)
    first_trainers = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 6, 1, 8, 30, 0),
                                 description: "Bright Eyes")
    second_trainers = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 6, 8, 9, 0, 0),
                                  description: "Dim Eyes")
    sign_up(trainer, first_trainers)
    sign_up(trainer, second_trainers)
    sign_up(person(:retired_ranger), second_trainers)

    # Right time, wrong description: never matches.
    decoy = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0),
                        description: "Wrong Eyes")
    sign_up(person(:echelon_ranger), decoy)

    report = Training::CapacityReport.execute(@training, YEAR)

    assert_equal [1, 2], report.rows.map(&:trainer_count)
    # The same trainer taught both sessions; the decoy trainer never counts.
    assert_equal 2, report.unique_trainers
  end

  test "totals sum pass counts over ended sessions only" do
    ended = create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), max: 2)
    passed = sign_up(person(:active_ranger), ended)
    sign_up(person(:retired_ranger), ended)
    TraineeStatus.create!(person_id: passed.id, slot_id: ended.id, status: TraineeStatus::STATUS_PASSED)

    upcoming = create_slot(@training, begins: Time.zone.local(YEAR, 9, 1, 9, 0, 0), max: 2)
    premature = sign_up(person(:alpha_ranger), upcoming)
    sign_up(person(:prospective_ranger), upcoming)
    # A premature score on a session that has not ended stays out of the totals.
    TraineeStatus.create!(person_id: premature.id, slot_id: upcoming.id, status: TraineeStatus::STATUS_PASSED)

    totals = Training::CapacityReport.execute(@training, YEAR).totals

    assert_equal 4, totals.signed_up
    assert_equal 4, totals.max
    assert_equal 100, totals.filled
    assert_equal 1, totals.passed
    assert_equal 1, totals.not_passed
  end

  test "HQ Full Training folds in the refresher sessions" do
    hq_full = Position.create!(id: Position::HQ_FULL_TRAINING, title: "HQ Full Training",
                               type: Position::TYPE_TRAINING, active: true)
    refresher = Position.create!(id: Position::HQ_REFRESHER_TRAINING, title: "HQ Refresher Training",
                                 type: Position::TYPE_TRAINING, active: true)
    full_slot = create_slot(hq_full, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0))
    refresher_slot = create_slot(refresher, begins: Time.zone.local(YEAR, 6, 8, 9, 0, 0))

    rows = Training::CapacityReport.execute(hq_full, YEAR).rows

    assert_equal [full_slot.id, refresher_slot.id], rows.map { |row| row.slot.id }
  end

  test "inactive sessions are excluded" do
    create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), active: false)
    active_slot = create_slot(@training, begins: Time.zone.local(YEAR, 6, 8, 9, 0, 0))

    rows = Training::CapacityReport.execute(@training, YEAR).rows

    assert_equal [active_slot.id], rows.map { |row| row.slot.id }
  end

  private

  # Same signature as TrainingSessionTestHelper#sign_up, so the two can
  # never be co-included with swapped argument orders.
  def sign_up(signee, slot)
    PersonSlot.create!(person_id: signee.id, slot_id: slot.id)
    signee
  end

  def record_status(subject, new_status, at:)
    PersonStatus.create!(person_id: subject.id, old_status: "suspended",
                         new_status:, created_at: at)
  end
end
