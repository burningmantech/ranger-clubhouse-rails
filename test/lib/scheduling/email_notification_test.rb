# frozen_string_literal: true

require "test_helper"

# Which sign-up changes queue the lead trainers' email.
class Scheduling::EmailNotificationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers
  include TrainingSlotTestHelper

  YEAR = 2026
  ADDED = TrainerRosterChangeJob::ADDED

  setup do
    travel_to Time.zone.local(YEAR, 8, 1, 12, 0, 0)
    Current.reset
    Current.person = person(:retired_ranger)

    @dirt = Position.create!(id: Position::TRAINING, title: "Training", type: Position::TYPE_TRAINING, active: true)
    trainer = Position.create!(id: Position::TRAINER, title: "Trainer", type: Position::TYPE_TRAINING, active: true)

    begins = Time.zone.local(YEAR, 8, 8, 9, 0, 0)
    @session = create_slot(@dirt, begins:, description: "Bright Eyes")
    @trainer_slot = create_slot(trainer, begins:, description: "Bright Eyes")

    @lead = person(:active_ranger)
    @trainer = person(:inactive_ranger)
    sign_up(@lead, @trainer_slot)
    @lead_row = TrainerStatus.create!(person_id: @lead.id, slot_id: @session.id, trainer_slot_id: @trainer_slot.id,
                                      status: TrainerStatus::STATUS_PENDING, is_lead: true)
  end

  teardown do
    Current.reset
    travel_back
  end

  test "a trainer slot change on a led session queues the email with the actor" do
    assert_enqueued_with(job: TrainerRosterChangeJob,
                         args: [@session, @trainer_slot, @trainer.id, ADDED, Current.person.id, nil]) do
      notify(@trainer_slot, @trainer)
    end
  end

  test "a session with no lead queues nothing" do
    @lead_row.update!(is_lead: false)

    assert_no_enqueued_jobs(only: TrainerRosterChangeJob) { notify(@trainer_slot, @trainer) }
  end

  test "the only lead changing queues nothing" do
    assert_no_enqueued_jobs(only: TrainerRosterChangeJob) { notify(@trainer_slot, @lead) }
  end

  test "a trainee joining the session itself queues nothing" do
    assert_no_enqueued_jobs(only: TrainerRosterChangeJob) { notify(@session, @trainer) }
  end

  test "an ended session queues nothing" do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)

    assert_no_enqueued_jobs(only: TrainerRosterChangeJob) { notify(@trainer_slot, @trainer) }
  end

  test "a trainer removed through Scheduling::Signup queues the email" do
    sign_up(@trainer, @trainer_slot)
    @trainer_slot.update!(signed_up: 2)

    assert_enqueued_with(job: TrainerRosterChangeJob) do
      result = Scheduling::Signup.remove(@trainer, @trainer_slot)
      assert_kind_of Scheduling::Verdict::Removed, result.verdict
    end
  end

  private

  def notify(slot, person)
    Scheduling::EmailNotification.handle_trainer_roster_change(slot, person.id, ADDED)
  end
end
