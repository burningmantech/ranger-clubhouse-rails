# frozen_string_literal: true

require "test_helper"

class Admin::ActionLogsHelperTest < ActionView::TestCase
  include Admin::ActionLogsHelper
  include UiComponents::UiDataBlockHelper
  include ButtonHelper

  test "action_log_pretty_data_block renders pretty printed json" do
    row = ActionLog.new(data: '{"alpha":1,"nested":{"beta":2}}')

    html = action_log_pretty_data_block(row).to_s

    assert_includes html, "<pre"
    assert_includes html, "&quot;alpha&quot;: 1"
    assert_includes html, "&quot;beta&quot;: 2"
    assert_includes html, "bg-base-100"
    assert_includes html, "text-base-content"
  end

  test "action_log_message_cell uses read more controls for long content" do
    row = ActionLog.new(id: 12, message: "A" * 80)

    html = action_log_message_cell(row).to_s

    assert_includes html, "data-controller=\"read-more\""
    assert_includes html, "action-log-message-12"
    assert_includes html, "Show More"
  end

  test "action_log_person_label links people and falls back to deleted ids" do
    person = person(:active_ranger)

    linked = action_log_person_label(person, person.id).to_s

    assert_includes linked, person_path(person)
    assert_includes linked, person.callsign
    assert_equal "Deleted #123", action_log_person_label(nil, 123)
  end

  test "action_log_metadata_items renders browser details as a summary" do
    row = ActionLog.new(ip: nil, user_agent: "Mozilla/5.0")
    row.browser = { platform: "macOS", browser: "Chrome", version: "123.0" }

    assert_equal [
      ["IP address", "server"],
      ["Browser", "Chrome • 123.0 • macOS"],
      ["User agent", "Mozilla/5.0"]
    ], action_log_metadata_items(row)
  end
end
