# frozen_string_literal: true

require "test_helper"

class ContactMailerTest < ActionMailer::TestCase
  setup do
    @sender = person(:active_ranger)
    @recipient = person(:retired_ranger)
  end

  def send_message(message)
    ContactMailer.send_message(sender_person: @sender, person: @recipient,
                              message_subject: "Saying hello", contact_message: message)
  end

  test "the message carries both callsigns and the note" do
    mail = send_message("See you at the burn")

    assert_equal [@recipient.email], mail.to
    assert_equal "Saying hello", mail.subject
    assert_includes mail.body.to_s, @recipient.callsign
    assert_includes mail.body.to_s, @sender.callsign
    assert_includes mail.body.to_s, "See you at the burn"
  end

  test "a note is laid out as paragraphs" do
    body = send_message("first line\n\nsecond line").body.to_s

    assert_includes body, "<p>first line</p>"
    assert_includes body, "<p>second line</p>"
  end

  test "a note cannot bring a script with it" do
    body = send_message("<script>alert(1)</script>").body.to_s

    assert_not_includes body, "<script"
    assert_includes body, "alert(1)", "the words should survive even though the tag does not"
  end

  test "a value the message shows plainly is escaped" do
    sender = Person.new(callsign: "<b>Hardly</b>", email: "sender@example.com")
    mail = ContactMailer.send_message(sender_person: sender, person: @recipient,
                                      message_subject: "Saying hello", contact_message: "hello")

    assert_includes mail.body.to_s, "&lt;b&gt;Hardly&lt;/b&gt;"
  end

  test "a piece shared with other messages is included" do
    assert_includes send_message("hello").body.to_s, "DO NOT REPLY TO THIS MESSAGE"
  end
end
