# frozen_string_literal: true

require "test_helper"

class UiStatBoxHelperTest < ActionView::TestCase
  include UiComponents::UiStatBoxHelper

  test "ui_stat_link wraps the box in a link named by its aria label" do
    render inline: <<~ERB
      <%= ui_stat_link "/quartermaster/swag-distribution?category=shirt",
                       aria_label: "12 shirts — show recipients" do %>
        <%= ui_stat_box "12", "Shirts" %>
      <% end %>
    ERB

    link = css_select("a[href='/quartermaster/swag-distribution?category=shirt']").sole
    assert_equal "12 shirts — show recipients", link["aria-label"]
    # no-decoration keeps the global link underline off the count and the label;
    # the ring stands in for the focus outline that goes with it.
    assert_equal %w[block focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2
                    focus-visible:ring-primary no-decoration rounded-lg],
                 link["class"].split.sort
    assert_select "a > div", text: /12\s*Shirts/
  end

  test "ui_stat_link adds a caller's classes to its own" do
    render inline: <<~ERB
      <%= ui_stat_link("/x", aria_label: "X", class: "hover:ring-2 hover:ring-primary") { ui_stat_box "1", "X" } %>
    ERB

    classes = css_select("a[href='/x']").sole["class"].split
    assert_includes classes, "hover:ring-2"
    assert_includes classes, "no-decoration"
  end

  test "only the active tile carries the filter ring" do
    render inline: <<~ERB
      <%= ui_stat_link("/pending", aria_label: "Pending", active: true) { ui_stat_box "3", "Pending" } %>
      <%= ui_stat_link("/callsign", aria_label: "Callsign") { ui_stat_box "4", "Callsign" } %>
    ERB

    active = css_select("a[href='/pending']").sole["class"].split
    assert_includes active, "ring-2"
    assert_includes active, "ring-primary"
    assert_not_includes css_select("a[href='/callsign']").sole["class"].split, "ring-2"
  end
end
