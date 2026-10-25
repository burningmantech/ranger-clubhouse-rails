# frozen_string_literal: true

require "test_helper"

class TrainingSessionFullMailerTest < ActionMailer::TestCase
  include TrainingSlotTestHelper

  setup do
    @slot = create_slot(positions(:training_lead), begins: Time.zone.local(2026, 8, 20, 9, 0, 0), description: "Bright Eyes")
  end

  test "notify tells the position's contact which session filled" do
    mail = TrainingSessionFullMailer.notify(slot: @slot, signed_up: 21, notify_email: "training@example.com")

    assert_equal ["training@example.com"], mail.to
    assert_equal "Ranger Clubhouse <#{EmailAddresses::DO_NOT_REPLY}>", mail[:from].to_s
    assert_equal ["training@example.com"], mail.reply_to
    assert_equal "[Clubhouse] A training session has become full", mail.subject

    body = mail.body.to_s
    assert_includes body, "Training Lead - Bright Eyes"
    assert_includes body, "Thursday Aug 20 2026 @ 09:00"
    assert_includes body, "<b>Signups:</b> 21<br>"
    assert_includes body, "<b>Max:</b> 20<br>"
  end

  # A position's contact address may be a comma-separated list. Everyone on it
  # hears, and a reply reaches them all. The message comes from the
  # do-not-reply address: SES sends only from an address it has verified.
  test "notify reaches every contact address, and replies go to all of them" do
    mail = TrainingSessionFullMailer.notify(slot: @slot, signed_up: 20, notify_email: "a@example.com, b@example.com")

    assert_equal ["a@example.com", "b@example.com"], mail.to
    assert_equal "Ranger Clubhouse <#{EmailAddresses::DO_NOT_REPLY}>", mail[:from].to_s
    assert_equal ["a@example.com", "b@example.com"], mail.reply_to
  end
end
