# frozen_string_literal: true

require "test_helper"

# The two rules the eight training reports used to restate for themselves, now
# stated once. Both are invisible on the dev data -- every 2026 slot carries a
# description, and a converted time still looks like a time -- so they get a
# test rather than a screenshot.
class Training::SessionLinkHelperTest < ActionView::TestCase
  tests Training::SessionLinkHelper
  include DateTimeHelper

  # Supplied by Training::BaseController as a helper_method in the real views.
  def training_slug = "green-dot"

  SlotDouble = Struct.new(:id, :begins, :timezone, :timezone_abbr, :description)

  # A London session, deliberately outside the app zone.
  def slot(description: "Zoom from London, UK")
    SlotDouble.new(31005, Time.utc(2026, 5, 30, 19, 0), "Europe/London", "BST", description)
  end

  test "stamps begins in the session's own zone instead of converting it" do
    # 19:00 is already London wall-clock. Slot#begins_adjusted would convert and
    # land on some other hour -- Green Dot's sessions span seven zones, so the
    # digits must survive untouched. (datetime_format hangs the app-zone
    # equivalent off a title attribute; only the visible stamp is asserted.)
    assert_equal "Sat May 30 @ 19:00 (BST)",
                 Nokogiri::HTML5.fragment(training_session_time(slot)).text
  end

  test "falls back when a slot has no description" do
    # Descriptions are NULL on real slots.
    [nil, ""].each do |empty|
      assert_includes training_session_link(slot(description: empty)), "(no description)"
    end
  end

  test "links the time to the session page and keeps the description out of the link" do
    html = Nokogiri::HTML5.fragment(training_session_link(slot, year: 2026))
    link = html.at_css("a")

    assert_equal "/training/green-dot/session/31005?year=2026", link[:href]
    assert_equal "Sat May 30 @ 19:00 (BST)", link.text.strip
    assert_includes html.text, "Zoom from London, UK"
  end

  test "links to the session a trainer slot teaches, not the trainer slot" do
    html = Nokogiri::HTML5.fragment(training_session_link(slot, session_id: 30968))

    assert_equal "/training/green-dot/session/30968", html.at_css("a")[:href]
  end

  test "renders the time as plain text when there is no session page" do
    html = Nokogiri::HTML5.fragment(training_session_link(slot, linkable: false))

    assert_nil html.at_css("a")
    assert_includes html.text, "Sat May 30 @ 19:00 (BST)"
  end

  test "appends block content after the description" do
    html = training_session_link(slot) { "<b>Green Dot Trainer</b>".html_safe }

    assert_operator html.index("Zoom from London, UK"), :<, html.index("Green Dot Trainer")
  end
end
