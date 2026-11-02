# frozen_string_literal: true

require "test_helper"

class BugReportMailerTest < ActionMailer::TestCase
  setup do
    @reporter = person(:active_ranger)
  end

  def notify(description: "The Save button does nothing.", email: @reporter.email)
    BugReportMailer.notify(callsign: @reporter.callsign, email:, browser: "Chrome 126 · Mac OS X 10.15.7",
                           page: "/me/timesheet", description:)
  end

  test "the Tech Cadre hears who filed it, how to reach them, and on what browser" do
    mail = notify

    assert_equal [EmailAddresses::TECH_CADRE], mail.to
    assert_equal [@reporter.email], mail.reply_to
    assert_equal "[Clubhouse] Bug report from #{@reporter.callsign}", mail.subject

    body = mail.body.to_s
    assert_includes body, "#{@reporter.callsign} filed a bug report."
    assert_includes body, "mailto:#{@reporter.email}"
    assert_includes body, "Browser: Chrome 126 · Mac OS X 10.15.7<br>"
    assert_includes body, "Page: /me/timesheet"
    assert_includes body, "<p>The Save button does nothing.</p>"
  end

  test "what the reporter typed is shown as text, never as markup" do
    body = notify(description: %(NoMethodError for Array<Person> <img src="https://tracker.example/p.gif">)).body.to_s

    assert_includes body, "NoMethodError for Array&lt;Person&gt;"
    assert_includes body, "&lt;img src="
    assert_not_includes body, %(<img src="https://tracker.example)
  end

  test "an address the mail library cannot take is left off the reply" do
    assert_nil notify(email: "...@example.com").reply_to
  end
end
