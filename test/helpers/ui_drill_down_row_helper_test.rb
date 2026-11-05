# frozen_string_literal: true

require "test_helper"

class UiDrillDownRowHelperTest < ActionView::TestCase
  include UiComponents::UiDrillDownRowHelper
  include UiComponents::BadgeHelper
  include IconHelper

  test "ui_drill_down_row renders a linked box with a headline and chevron" do
    render inline: <<~ERB
      <%= ui_drill_down_row "/scheduling/slots/position/1", "Dirt - Green Dot",
                            meta: "12 slots" %>
    ERB

    assert_select "a.no-decoration.box.box-default.box-hover[href='/scheduling/slots/position/1']", count: 1
    assert_select "a > div > div.text-lg.font-semibold", text: /Dirt - Green Dot/
    assert_select "a span.text-stone-subtle", text: "12 slots"
    assert_select "a > div.text-xl i.fa-arrow-right", count: 1
  end

  test "ui_drill_down_row separates each headline segment with a bullet" do
    render inline: <<~ERB
      <%= ui_drill_down_row "/x", "Other", meta: "3 items",
                            badges: ui_badge("1 inactive", :warning, size: "base") %>
    ERB

    assert_select "div.text-lg > span.my-1", count: 2, text: "•"
    assert_select "span.badge", text: "1 inactive"
    # The segments are inline, so the bullets need whitespace around them or
    # they butt against the text: "Other•3 items".
    assert_match(/Other <span class="my-1">•<\/span> <span/, rendered)
  end

  test "ui_drill_down_row omits the meta segment and its bullet when absent" do
    render inline: <<~ERB
      <%= ui_drill_down_row "/x", "Just a title" %>
    ERB

    assert_select "span.my-1", count: 0
    assert_select "span.text-stone-subtle", count: 0
  end

  test "ui_drill_down_row accepts several badges" do
    render inline: <<~ERB
      <%= ui_drill_down_row "/x", "Two badges",
                            badges: [ui_badge("one", :success), ui_badge("two", :error)] %>
    ERB

    assert_select "span.badge", count: 2
    assert_select "span.my-1", count: 2
  end

  # A conditional badge passes nil rather than being wrapped in an if at the
  # call site, so a nil must not leave a dangling bullet behind.
  test "ui_drill_down_row ignores a nil badge" do
    render inline: <<~ERB
      <%= ui_drill_down_row "/x", "No badge", meta: "3 items", badges: nil %>
    ERB

    assert_select "span.badge", count: 0
    assert_select "span.my-1", count: 1
  end

  # Figures sit beside the headline as a ledger in a wrapping row: numerals in a
  # fixed right-aligned cell so they line up down the list, and a zero recedes.
  test "ui_drill_down_row renders figures as a ledger beside the headline, muting a zero" do
    render inline: <<~ERB
      <%= ui_drill_down_row "/x", "Dirt", figures: [[0, "upcoming"], [3, "past"]] %>
    ERB

    assert_select "a > div.flex-wrap > div.grow + div.tabular-nums", count: 1
    assert_select "a > div.flex-wrap + div.text-xl", count: 1
    assert_select "div.tabular-nums > span", count: 2
    # Inline spans again: without the joining space a screen reader hears "0upcoming".
    assert_select "div.tabular-nums > span:first-child", text: "0 upcoming"
    assert_select "div.tabular-nums > span:first-child > span.min-w-9.text-right.text-stone-subtle", text: "0"
    assert_select "div.tabular-nums > span:last-child > span.min-w-9.text-right.font-semibold", text: "3"
    assert_select "span.my-1", count: 0
  end

  test "ui_drill_down_row ignores a nil figure" do
    render inline: <<~ERB
      <%= ui_drill_down_row "/x", "Dirt", figures: [[2, "upcoming"], nil] %>
    ERB

    assert_select "div.tabular-nums > span", count: 1
  end

  # A flat pair, a non-Integer count or a blank label would 500 the whole index
  # from inside the render; and one count belongs in the headline, not two.
  test "ui_drill_down_row refuses malformed figures and figures beside meta" do
    assert_raises(ArgumentError) { ui_drill_down_row("/x", "Dirt", figures: [3, "past"]) }
    assert_raises(ArgumentError) { ui_drill_down_row("/x", "Dirt", figures: [["3", "past"]]) }
    assert_raises(ArgumentError) { ui_drill_down_row("/x", "Dirt", figures: [[3, ""]]) }
    assert_raises(ArgumentError) { ui_drill_down_row("/x", "Dirt", meta: "3 shifts", figures: [[3, "past"]]) }
  end

  test "ui_drill_down_row takes a custom icon and passes attributes to the link" do
    render inline: <<~ERB
      <%= ui_drill_down_row "/x", "Elsewhere", icon: "ban", class: "mt-4",
                            data: { testid: "row" } %>
    ERB

    assert_select "a.mt-4[data-testid='row']", count: 1
    assert_select "a i.fa-ban", count: 1
    assert_select "i.fa-arrow-right", count: 0
  end

  # `disabled` on an <a> is inert, so a row that goes nowhere has to stop being
  # a link — otherwise it stays clickable and in the tab order.
  test "ui_drill_down_row blocked renders no link at all" do
    render inline: <<~ERB
      <%= ui_drill_down_row "/x", "Training", meta: "2 shifts", blocked: true do %>
        <div class="text-error">Finish the Online Course first.</div>
      <% end %>
    ERB

    assert_select "a", count: 0
    assert_select "div[aria-disabled='true']", count: 1
    assert_select "div.cursor-not-allowed", count: 1
    assert_select "div.text-error", text: "Finish the Online Course first."
    assert_no_match "href", rendered
  end

  test "ui_drill_down_row blocked defaults to the ban icon and drops the hover affordance" do
    render inline: <<~ERB
      <%= ui_drill_down_row "/x", "Training", blocked: true %>
    ERB

    assert_select "i.fa-ban", count: 1
    assert_select "i.fa-arrow-right", count: 0
    assert_no_match "box-hover", rendered
  end

  test "ui_drill_down_row is a followable link when not blocked" do
    render inline: <<~ERB
      <%= ui_drill_down_row "/x", "Training", blocked: false %>
    ERB

    assert_select "a.box-hover[href='/x']", count: 1
    assert_select "[aria-disabled]", count: 0
    assert_select "i.fa-arrow-right", count: 1
  end

  test "ui_drill_down_row renders block content below the headline" do
    render inline: <<~ERB
      <%= ui_drill_down_row "/x", "Training", meta: "2 shifts" do %>
        <div class="text-error">Finish the Online Course first.</div>
      <% end %>
    ERB

    assert_select "a > div > div.text-lg", text: /Training/
    assert_select "a > div > div.text-error", text: "Finish the Online Course first."
  end

  test "ui_drill_down_row requires a title" do
    assert_raises(ArgumentError) { ui_drill_down_row("/x", "") }
  end
end
