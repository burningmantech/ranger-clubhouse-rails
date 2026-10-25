# frozen_string_literal: true

require "test_helper"

# The mailer has no caller yet; these pin who it reaches and who replies go to.
class TrainerReminderMailerTest < ActionMailer::TestCase
  include TrainingSlotTestHelper

  setup do
    @slot = create_slot(positions(:training_lead), begins: Time.zone.local(2026, 8, 20, 9, 0, 0), description: "Bright Eyes")
  end

  test "notify reaches the contact and the trainers, from the do-not-reply address" do
    @slot.position.contact_email = "training@example.com"

    mail = TrainerReminderMailer.notify(slot: @slot, trainer_emails: ["trainer@example.com"])

    assert_equal ["training@example.com", "trainer@example.com"], mail.to
    assert_equal "Ranger Clubhouse <#{EmailAddresses::DO_NOT_REPLY}>", mail[:from].to_s
    assert_equal ["training@example.com"], mail.reply_to
    assert_equal "[Clubhouse] Record Training Results Reminder", mail.subject
    assert_includes mail.body.to_s, "Training Lead - Bright Eyes"
  end

  # SES sends only from an address it has verified, so no contact address
  # signs the message, however many there are.
  test "a contact list is reached in full, and replies go to all of it" do
    @slot.position.contact_email = "a@example.com, b@example.com"

    mail = TrainerReminderMailer.notify(slot: @slot, trainer_emails: [])

    assert_equal ["a@example.com", "b@example.com"], mail.to
    assert_equal "Ranger Clubhouse <#{EmailAddresses::DO_NOT_REPLY}>", mail[:from].to_s
    assert_equal ["a@example.com", "b@example.com"], mail.reply_to
  end
end
