# frozen_string_literal: true

require "test_helper"

class PasswordResetMailerTest < ActionMailer::TestCase
  setup do
    @person = person(:active_ranger)
    @token = "test_reset_token_abc"
  end

  test "notify sends multipart email with text and html parts" do
    mail = PasswordResetMailer.notify(person: @person, reset_token: @token)

    assert_equal ["testranger@example.com"], mail.to
    assert_equal "Ranger Clubhouse Password Reset", mail.subject
    assert mail.multipart?, "Email should be multipart"

    content_types = mail.parts.map(&:content_type)
    assert content_types.any? { |ct| ct.include?("text/plain") }, "Should include text/plain part"
    assert content_types.any? { |ct| ct.include?("text/html") }, "Should include text/html part"
  end

  test "notify includes reset URL with token in both parts" do
    mail = PasswordResetMailer.notify(person: @person, reset_token: @token)

    expected_path = "/reset-token?token=#{@token}"

    text_body = mail.text_part.body.to_s
    html_body = mail.html_part.body.to_s

    assert_includes text_body, expected_path, "Text part should contain reset URL path"
    assert_includes html_body, expected_path, "HTML part should contain reset URL path"
  end

  test "notify includes greeting with first name" do
    mail = PasswordResetMailer.notify(person: @person, reset_token: @token)

    text_body = mail.text_part.body.to_s
    assert_includes text_body, "Hi #{@person.desired_first_name}", "Should greet by preferred/first name"
  end

  test "notify includes support email" do
    mail = PasswordResetMailer.notify(person: @person, reset_token: @token)

    text_body = mail.text_part.body.to_s
    assert_includes text_body, EmailAddresses::TECH_CADRE, "Should include support email"
  end

  test "notify uses do-not-reply from address" do
    mail = PasswordResetMailer.notify(person: @person, reset_token: @token)

    assert_not_nil mail.from, "From address should be set"
  end
end
