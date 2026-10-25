# frozen_string_literal: true

require "test_helper"

class MailLogHelperTest < ActionView::TestCase
  # Both mail logs print this sentence, and the nightly cleanup is what makes it
  # true. Changing MailLog::RETENTION changes the words here on its own; this
  # holds them to the window as it is written today.
  test "the retention note says the cleanup's window in words" do
    assert_equal 6.months, MailLog::RETENTION
    assert_equal "Only the last 6 months of messages are kept.", mail_log_retention_note
  end

  # The third stat box counts that same window, so it takes its name from it.
  test "the retained-messages box is named by the same window" do
    assert_equal "Last 6 Months", mail_log_retained_label
  end
end
