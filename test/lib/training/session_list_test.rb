# frozen_string_literal: true

require "test_helper"

# Training::SessionList: the upcoming/past partition (with the same-day grace
# window) and the exact-description-within-the-hour trainer group matching.
class Training::SessionListTest < ActiveSupport::TestCase
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

  test "sessions split into upcoming and past on the day after they end" do
    past = create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0))
    upcoming = create_slot(@training, begins: Time.zone.local(YEAR, 9, 1, 9, 0, 0))
    # Ended earlier today: the same-day grace window keeps it manageable.
    ended_today = create_slot(@training, begins: Time.zone.local(YEAR, 8, 10, 1, 0, 0),
                              ends: Time.zone.local(YEAR, 8, 10, 9, 0, 0))
    # A different year must not appear at all.
    create_slot(@training, begins: Time.zone.local(YEAR - 1, 6, 1, 9, 0, 0))

    upcoming_sessions, past_sessions = Training::SessionList.execute(@training, YEAR)

    assert_equal [ended_today.id, upcoming.id].sort, upcoming_sessions.map { |s| s.slot.id }.sort
    assert_equal [past.id], past_sessions.map { |s| s.slot.id }
  end

  test "a trainer group matches on exact description within the hour window" do
    session = create_slot(@training, begins: Time.zone.local(YEAR, 9, 1, 9, 0, 0), description: "Bright Eyes")
    trainer_slot = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 9, 1, 8, 30, 0),
                               description: "Bright Eyes")
    trainer = person(:active_ranger)
    PersonSlot.create!(person_id: trainer.id, slot_id: trainer_slot.id)
    TrainerStatus.create!(person_id: trainer.id, slot_id: session.id,
                          trainer_slot_id: trainer_slot.id, is_lead: true)

    upcoming_sessions, = Training::SessionList.execute(@training, YEAR)
    groups = upcoming_sessions.first.trainer_groups

    assert_equal 1, groups.size
    assert_equal "Green Dot Trainer", groups.first.position_title
    assert_equal [trainer.id], groups.first.trainers.map { |t| t.person.id }
    assert groups.first.trainers.first.is_lead
  end

  test "a different description or an out-of-window start leaves the session without groups" do
    session = create_slot(@training, begins: Time.zone.local(YEAR, 9, 1, 9, 0, 0), description: "Bright Eyes")
    # Wrong description, right time.
    create_slot(@trainer_position, begins: Time.zone.local(YEAR, 9, 1, 8, 30, 0), description: "Dim Eyes")
    # Right description, begins more than an hour early.
    create_slot(@trainer_position, begins: Time.zone.local(YEAR, 9, 1, 7, 30, 0), description: "Bright Eyes")

    upcoming_sessions, = Training::SessionList.execute(@training, YEAR)

    assert_equal [session.id], upcoming_sessions.map { |s| s.slot.id }
    assert_empty upcoming_sessions.first.trainer_groups
  end

  test "HQ Full Training folds in the refresher sessions" do
    hq_full = Position.create!(id: Position::HQ_FULL_TRAINING, title: "HQ Full Training",
                               type: Position::TYPE_TRAINING, active: true)
    Position.create!(id: Position::HQ_REFRESHER_TRAINING, title: "HQ Refresher Training",
                     type: Position::TYPE_TRAINING, active: true)
    refresher_slot = create_slot(Position.find(Position::HQ_REFRESHER_TRAINING),
                                 begins: Time.zone.local(YEAR, 9, 2, 9, 0, 0))

    upcoming_sessions, = Training::SessionList.execute(hq_full, YEAR)

    assert_equal [refresher_slot.id], upcoming_sessions.map { |s| s.slot.id }
  end
end
