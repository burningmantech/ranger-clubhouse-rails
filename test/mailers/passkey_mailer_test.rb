# frozen_string_literal: true

require "test_helper"

class PasskeyMailerTest < ActionMailer::TestCase
  setup do
    @person = person(:active_ranger)
    @admin = person(:auditor_ranger)
  end

  test "added by the person themselves says so, and that there is nothing to do" do
    mail = PasskeyMailer.added(person: @person, nickname: "My Phone", by: @person)

    assert_equal [@person.email], mail.to
    assert_equal "A passkey was added to your Ranger Clubhouse account", mail.subject
    assert mail.multipart?, "the notice should carry both a text and an html part"

    [mail.text_part.body.to_s, mail.html_part.body.to_s].each do |body|
      assert_includes body, "Hi #{@person.desired_first_name}"
      assert_includes body, "My Phone"
      assert_match(/added to your Ranger Clubhouse account\s+by you/, body)
      assert_includes body, "If that was you, there is nothing to do."
      assert_not_includes body, "Clubhouse Admin"
      assert_includes body, EmailAddresses::TECH_CADRE
    end
  end

  test "added by an Admin names the Admin" do
    mail = PasskeyMailer.added(person: @person, nickname: "HQ Security Key", by: @admin)

    assert_equal [@person.email], mail.to
    [mail.text_part.body.to_s, mail.html_part.body.to_s].each do |body|
      assert_match(/by #{Regexp.escape(@admin.callsign)}, a Clubhouse Admin/, body)
      assert_includes body, "If you were expecting it, there is nothing to do."
      assert_not_includes body, "by you"
    end
  end

  test "removed says what still signs in and what is left to do" do
    mail = PasskeyMailer.removed(person: @person, nickname: "Old Phone", by: @person)

    assert_equal "A passkey was removed from your Ranger Clubhouse account", mail.subject
    [mail.text_part.body.to_s, mail.html_part.body.to_s].each do |body|
      assert_includes body, "Old Phone"
      assert_match(/removed from your Ranger Clubhouse account\s+by you/, body)
      assert_includes body, "Your password and any other passkeys still can."
      assert_includes body, "delete Old Phone from your device or password manager"
      assert_includes body, "If you did not remove it, change your password as well."
    end
  end

  test "removed by an Admin names the Admin" do
    mail = PasskeyMailer.removed(person: @person, nickname: "Old Phone", by: @admin)

    [mail.text_part.body.to_s, mail.html_part.body.to_s].each do |body|
      assert_match(/by #{Regexp.escape(@admin.callsign)}, a Clubhouse Admin/, body)
      assert_not_includes body, "If you did not remove it"
    end
  end

  # The nickname is typed by a person and lands in an HTML message.
  test "a nickname cannot bring markup into the message" do
    mail = PasskeyMailer.added(person: @person, nickname: "<script>alert(1)</script>", by: @person)

    assert_not_includes mail.html_part.body.to_s, "<script>alert(1)</script>"
    assert_includes mail.html_part.body.to_s, "&lt;script&gt;"
  end

  # A security notice that teaches people to follow its link is a gift to
  # whoever forges the next one. It names the place instead.
  test "the notice points at the Account menu and carries no link into the Clubhouse" do
    [PasskeyMailer.added(person: @person, nickname: "My Phone", by: @person),
     PasskeyMailer.removed(person: @person, nickname: "My Phone", by: @person)].each do |mail|
      assert_no_match(%r{/me/profile|/passkey}, mail.html_part.body.to_s)
      assert_no_match(%r{https?://\S*passkey}, mail.text_part.body.to_s)
    end
    assert_includes PasskeyMailer.added(person: @person, nickname: "My Phone", by: @person).text_part.body.to_s,
                    "open the Account menu, choose Passkeys"
  end
end
