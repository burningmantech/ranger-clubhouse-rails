# frozen_string_literal: true

require "test_helper"

class AlertTest < ActiveSupport::TestCase
  test "find_all lists on playa alerts first, then by title" do
    listed = Alert.find_all.pluck(:on_playa, :title)

    assert_equal listed.sort_by { |on_playa, title| [on_playa ? 0 : 1, title] }, listed
  end

  test "a title and a description are both required" do
    alert = Alert.new(title: "", description: "")

    assert_not alert.valid?
    assert_equal ["Enter a title for the alert.", "Describe what the alert tells a Ranger."],
                 alert.errors.full_messages
  end

  test "a title longer than the column is rejected" do
    alert = Alert.new(title: "T" * 256, description: "Something.")

    assert_not alert.valid?
  end

  test "surrounding whitespace is trimmed before saving" do
    alert = Alert.create!(title: "  Ticketing  ", description: "Tickets are ready.\r\n")

    assert_equal "Ticketing", alert.title
    assert_equal "Tickets are ready.", alert.description
  end
end
