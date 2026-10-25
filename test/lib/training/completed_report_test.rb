# frozen_string_literal: true

require "test_helper"

# Training::CompletedReport: the ended-and-active session list, the passed-only
# trainee roster, the one-hour-window trainer matching, and the season totals.
class Training::CompletedReportTest < ActiveSupport::TestCase
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

  test "lists active ended sessions, including ones no one passed" do
    ended = create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0))
    unscored = create_slot(@training, begins: Time.zone.local(YEAR, 6, 8, 9, 0, 0))
    create_slot(@training, begins: Time.zone.local(YEAR, 9, 1, 9, 0, 0))
    create_slot(@training, begins: Time.zone.local(YEAR, 6, 15, 9, 0, 0), active: false)

    pass(person(:active_ranger), ended)

    report = Training::CompletedReport.execute(@training, YEAR)

    # Upcoming and inactive sessions are out; the unscored one stays at zero.
    assert_equal [ended.id, unscored.id], report.sessions.map { |session| session.slot.id }
    assert_equal [1, 0], report.sessions.map { |session| session.trainees.size }
  end

  test "only people marked passed are listed, sorted by callsign" do
    slot = create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0))

    zebra = pass(person(:active_ranger), slot)
    zebra.update!(callsign: "Zebra")
    apple = pass(person(:retired_ranger), slot)
    apple.update!(callsign: "apple")

    # Scored but did not pass.
    TraineeStatus.create!(person_id: person(:echelon_ranger).id, slot_id: slot.id, status: TraineeStatus::STATUS_NOT_PASSED)

    session = Training::CompletedReport.execute(@training, YEAR).sessions.first

    assert_equal [apple.id, zebra.id], session.trainees.map(&:id)
  end

  test "trainers come from attended statuses matched by the one-hour window" do
    slot = create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: "Bright Eyes")
    pass(person(:active_ranger), slot)

    trainer_slot = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 6, 1, 8, 30, 0),
                               description: "Bright Eyes")
    attended = attend(person(:retired_ranger), slot, trainer_slot)
    # Same slot, but never showed.
    TrainerStatus.create!(person_id: person(:alpha_ranger).id, slot_id: slot.id,
                          trainer_slot_id: trainer_slot.id,
                          status: TrainerStatus::STATUS_NO_SHOW)

    # Right time, wrong description -- outside the match rule.
    decoy = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0),
                        description: "Wrong Eyes")
    attend(person(:echelon_ranger), slot, decoy)

    # Right description, but begins more than an hour before the session.
    early = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 6, 1, 7, 0, 0),
                        description: "Bright Eyes")
    attend(person(:prospective_ranger), slot, early)

    session = Training::CompletedReport.execute(@training, YEAR).sessions.first

    assert_equal [attended.id], session.trainers.map(&:id)
  end

  test "totals count attendance across every session" do
    first = create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: "Playa")
    second = create_slot(@training, begins: Time.zone.local(YEAR, 6, 8, 9, 0, 0), description: "Playa")

    repeat = person(:active_ranger)
    pass(repeat, first)
    pass(repeat, second)
    pass(person(:retired_ranger), first)

    trainer = person(:echelon_ranger)
    first_trainers = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 6, 1, 8, 30, 0),
                                 description: "Playa")
    second_trainers = create_slot(@trainer_position, begins: Time.zone.local(YEAR, 6, 8, 8, 30, 0),
                                  description: "Playa")
    attend(trainer, first, first_trainers)
    attend(trainer, second, second_trainers)

    report = Training::CompletedReport.execute(@training, YEAR)

    # The repeat trainee and the repeat trainer each count once per session.
    assert_equal 3, report.trainee_count
    assert_equal 2, report.trainer_count
  end

  test "HQ Full Training folds in the refresher sessions" do
    hq_full = Position.create!(id: Position::HQ_FULL_TRAINING, title: "HQ Full Training",
                               type: Position::TYPE_TRAINING, active: true)
    refresher = Position.create!(id: Position::HQ_REFRESHER_TRAINING, title: "HQ Refresher Training",
                                 type: Position::TYPE_TRAINING, active: true)
    full_slot = create_slot(hq_full, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0))
    refresher_slot = create_slot(refresher, begins: Time.zone.local(YEAR, 6, 8, 9, 0, 0))
    pass(person(:active_ranger), refresher_slot)

    report = Training::CompletedReport.execute(hq_full, YEAR)

    assert_equal [full_slot.id, refresher_slot.id], report.sessions.map { |session| session.slot.id }
    assert_equal 1, report.trainee_count
  end

  test "a year with no ended sessions reports nothing" do
    create_slot(@training, begins: Time.zone.local(YEAR, 9, 1, 9, 0, 0))

    report = Training::CompletedReport.execute(@training, YEAR)

    assert_empty report.sessions
    assert_equal 0, report.trainee_count
    assert_equal 0, report.trainer_count
  end

  private

  def pass(trainee, slot)
    TraineeStatus.create!(person_id: trainee.id, slot_id: slot.id, status: TraineeStatus::STATUS_PASSED)
    trainee
  end

  def attend(trainer, slot, trainer_slot)
    TrainerStatus.create!(person_id: trainer.id, slot_id: slot.id, trainer_slot_id: trainer_slot.id,
                          status: TrainerStatus::STATUS_ATTENDED)
    trainer
  end
end
