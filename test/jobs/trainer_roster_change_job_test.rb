# frozen_string_literal: true

require "test_helper"

class TrainerRosterChangeJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  include ActiveSupport::Testing::TimeHelpers
  include TrainingSlotTestHelper

  YEAR = 2026
  ADDED = TrainerRosterChangeJob::ADDED
  REMOVED = TrainerRosterChangeJob::REMOVED

  setup do
    travel_to Time.zone.local(YEAR, 8, 1, 12, 0, 0)
    Current.reset
    ActionMailer::Base.deliveries.clear

    dirt = Position.create!(id: Position::TRAINING, title: "Training", type: Position::TYPE_TRAINING,
                            active: true, contact_email: "academy@example.com")
    trainer = Position.create!(id: Position::TRAINER, title: "Trainer", type: Position::TYPE_TRAINING, active: true)

    begins = Time.zone.local(YEAR, 8, 8, 9, 0, 0)
    @session = create_slot(dirt, begins:, description: "Bright Eyes")
    @trainer_slot = create_slot(trainer, begins:, description: "Bright Eyes")

    @lead = person(:active_ranger)
    @trainer = person(:inactive_ranger)
    @actor = person(:retired_ranger)

    sign_up(@lead, @trainer_slot)
    mark_lead(@lead)
  end

  teardown do
    Current.reset
    travel_back
  end

  test "an added trainer is announced to the lead with the roster" do
    sign_up(@trainer, @trainer_slot)

    assert_emails 1 do
      TrainerRosterChangeJob.perform_now(@session, @trainer_slot, @trainer.id, ADDED, @actor.id)
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal [@lead.email], mail.to
    assert_equal ["academy@example.com"], mail.reply_to
    assert_equal "[Clubhouse] Trainer added: #{@trainer.callsign}, Bright Eyes, Sat Aug 8", mail.subject

    body = mail.body.to_s
    assert_includes body, "#{@trainer.callsign} (Trainer) is now signed up for a session you lead."
    assert_includes body, "Added by #{@actor.callsign}."
    assert_includes body, "Trainers Signed Up (2)"
    assert_includes body, "<b>Added</b>"
    assert_includes body, "/training/in-person/session/#{@session.id}"
  end

  test "a trainer who left on their own is announced without an actor" do
    assert_emails 1 do
      TrainerRosterChangeJob.perform_now(@session, @trainer_slot, @trainer.id, REMOVED, @trainer.id)
    end

    mail = ActionMailer::Base.deliveries.last
    assert_match(/\A\[Clubhouse\] Trainer removed: /, mail.subject)
    assert_includes mail.body.to_s, "#{@trainer.callsign} removed the shift from their schedule."
    assert_includes mail.body.to_s, "Trainers Signed Up (1)"
  end

  test "a sweep's reason is printed" do
    assert_emails 1 do
      TrainerRosterChangeJob.perform_now(@session, @trainer_slot, @trainer.id, REMOVED, @actor.id, "position revoked")
    end

    assert_includes ActionMailer::Base.deliveries.last.body.to_s, "Removed by #{@actor.callsign} (position revoked)."
  end

  # The wait before this job runs is there so an add-then-undo stays quiet.
  test "nothing is sent when the change was undone while it waited" do
    assert_emails 0 do
      TrainerRosterChangeJob.perform_now(@session, @trainer_slot, @trainer.id, ADDED, @actor.id)
    end

    sign_up(@trainer, @trainer_slot)

    assert_emails 0 do
      TrainerRosterChangeJob.perform_now(@session, @trainer_slot, @trainer.id, REMOVED, @actor.id)
    end
  end

  test "the lead who made the change is not told about it" do
    sign_up(@trainer, @trainer_slot)

    assert_emails 0 do
      TrainerRosterChangeJob.perform_now(@session, @trainer_slot, @trainer.id, ADDED, @lead.id)
    end
  end

  # A removed trainer keeps their trainer_status row.
  test "a lead no longer on the roster is not written to" do
    PersonSlot.where(person_id: @lead.id, slot_id: @trainer_slot.id).delete_all
    sign_up(@trainer, @trainer_slot)

    assert_emails 0 do
      TrainerRosterChangeJob.perform_now(@session, @trainer_slot, @trainer.id, ADDED, @actor.id)
    end
  end

  test "every other lead hears when a lead leaves" do
    second = person(:echelon_ranger)
    sign_up(second, @trainer_slot)
    mark_lead(second)
    PersonSlot.where(person_id: @lead.id, slot_id: @trainer_slot.id).delete_all

    assert_emails 1 do
      TrainerRosterChangeJob.perform_now(@session, @trainer_slot, @lead.id, REMOVED, @lead.id)
    end

    assert_equal [second.email], ActionMailer::Base.deliveries.last.to
  end

  test "nothing is sent once the session has ended" do
    sign_up(@trainer, @trainer_slot)
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)

    assert_emails 0 do
      TrainerRosterChangeJob.perform_now(@session, @trainer_slot, @trainer.id, ADDED, @actor.id)
    end
  end

  private

  def mark_lead(person)
    TrainerStatus.create!(person_id: person.id, slot_id: @session.id, trainer_slot_id: @trainer_slot.id,
                          status: TrainerStatus::STATUS_PENDING, is_lead: true)
  end
end
