# frozen_string_literal: true

require "test_helper"

class SidebarHelperTest < ActionView::TestCase
  include SidebarHelper
  include IconHelper

  setup do
    self.request = ActionDispatch::TestRequest.create
  end

  test "sidebar_item applies active styling for matching prefixes when active_prefix is enabled" do
    request.path = "/person/238/schedule/sign-ups"

    html = sidebar_item("Schedule / Sign-Ups", "/person/238/schedule", active_prefix: true)

    # The marker is CSS keyed on this class (components/sidebar.css); the
    # helper's job is to say which item is active, not to paint it.
    assert_match(/class="[^"]*\bactive\b[^"]*"/, html)
    assert_includes html, "aria-current=\"true\""
  end

  test "sidebar_item does not apply prefix styling without active_prefix" do
    request.path = "/person/238/schedule/sign-ups"

    html = sidebar_item("Schedule / Sign-Ups", "/person/238/schedule")

    assert_no_match(/class="[^"]*\bactive\b[^"]*"/, html)
  end

  test "sidebar_item does not match sibling prefixes when active_prefix is enabled" do
    request.path = "/person/238/schedule-export"

    html = sidebar_item("Schedule / Sign-Ups", "/person/238/schedule", active_prefix: true)

    assert_no_match(/class="[^"]*\bactive\b[^"]*"/, html)
    assert_not_includes html, "aria-current=\"true\""
  end

  test "sidebar_item emits the match prefix for the client-side active-link pass" do
    request.path = "/person/238/schedule/sign-ups"

    html = sidebar_item("Schedule / Sign-Ups", "/person/238/schedule?year=2026", active_prefix: true)
    assert_includes html, "data-active-prefix=\"/person/238/schedule\""

    assert_not_includes sidebar_item("Slots", "/scheduling/slots", active_prefix: true, root: true),
                        "data-active-prefix"
    assert_not_includes sidebar_item("Slots", "/scheduling/slots"), "data-active-prefix"
  end

  # A training's Sessions item is /training/<slug> but claims only the session/
  # pages beneath it. Handed its own path, the client pass lit it on every
  # sibling page (Capacity, Surveys, Mentoring) as well as the sibling's own item.
  test "sidebar_item hands the client the narrower prefix an item names, not its own path" do
    request.path = "/training/green-dot/capacity"

    html = sidebar_item("Sessions", "/training/green-dot?year=2026", active_prefix: "/training/green-dot/session")

    assert_includes html, "data-active-prefix=\"/training/green-dot/session\""
    assert_not_includes html, "aria-current=\"true\""
  end
end
