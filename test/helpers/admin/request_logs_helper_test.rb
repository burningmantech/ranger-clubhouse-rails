# frozen_string_literal: true

require "test_helper"

class Admin::RequestLogsHelperTest < ActionView::TestCase
  include Admin::RequestLogsHelper

  test "lays out a JSON payload so it can be read" do
    result = request_log_pretty_payload('{"grant_type":"refresh_token"}')

    assert_equal "{\n  \"grant_type\": \"refresh_token\"\n}", result
  end

  test "unwraps a payload that was encoded a second time" do
    stored = JSON.generate('{"errors":[{"title":"Invalid"}]}')

    result = request_log_pretty_payload(stored)

    assert_includes result, '"title": "Invalid"'
    assert_not_includes result, "\\\""
  end

  test "shows a payload that is not JSON exactly as stored" do
    assert_equal "<p>Try again</p>", request_log_pretty_payload("<p>Try again</p>")
  end

  test "shows an empty payload as nothing rather than raising" do
    assert_equal "", request_log_pretty_payload(nil)
  end
end
