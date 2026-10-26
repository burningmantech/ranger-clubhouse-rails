# frozen_string_literal: true

require "test_helper"

class FilterBarHelperTest < ActionView::TestCase
  include UiComponents::FilterBarHelper
  include UiComponents::BadgeHelper
  include ButtonHelper
  include IconHelper

  test "renders toggle button, chips, clear link, count, and hidden panel" do
    render inline: <<~ERB
      <%= filter_bar id: "slot-filters",
                     chips: [{ label: "Status: Active", url: "/slots?day=1" }],
                     clear_url: "/slots",
                     count: "Showing 1 of 2 slots" do %>
        <p>Panel form</p>
      <% end %>
    ERB

    assert_select "div#slot-filters" do
      assert_select "button[aria-controls='slot-filters-panel'][aria-expanded='false']" \
                    "[data-controller='toggle'][data-toggle-dom-id-value='slot-filters-panel']",
                    text: /Filters/ do
        assert_select "span.badge", text: "1"
      end
      assert_select "a[href='/slots?day=1'][aria-label='Remove filter: Status: Active']",
                    text: /Status: Active/
      assert_select "a[href='/slots']", text: "Clear All Filters"
      assert_select "span", text: "Showing 1 of 2 slots"
      assert_select "div#slot-filters-panel.hidden[aria-hidden='true']" do
        assert_select "p", text: "Panel form"
      end
    end
  end

  test "omits badge, chips, and clear link when no filters are active" do
    render inline: <<~ERB
      <%= filter_bar clear_url: "/slots" do %>
        <p>Panel form</p>
      <% end %>
    ERB

    assert_select "div#filter-bar" do
      assert_select "button[aria-controls='filter-bar-panel']", text: /Filters/
      assert_select "span.badge", count: 0
      assert_select "a", count: 0
    end
  end

  test "requires a block" do
    assert_raises(ArgumentError) { filter_bar }
  end

  # The page's export rides the end of the bar it is scoped by, after the
  # count, so the reader finds it where the narrowing happens.
  test "renders actions at the end of the row" do
    render inline: <<~ERB
      <%= filter_bar id: "slot-filters", count: "Showing 2 slots",
                     actions: button_link("Export CSV", :secondary, "/slots.csv") do %>
        <p>Panel form</p>
      <% end %>
    ERB

    assert_select "div#slot-filters > div > div.ms-auto" do
      assert_select "a[href='/slots.csv']", text: /Export CSV/
    end
  end

  test "renders every action given an array of them" do
    render inline: <<~ERB
      <%= filter_bar actions: [button_link("Roster", :secondary, "/roster.csv"),
                               button_link("Counts", :secondary, "/counts.csv")] do %>
        <p>Panel form</p>
      <% end %>
    ERB

    assert_select "div.ms-auto" do
      assert_select "a", count: 2
    end
  end

  # Pages pass their own visibility rule inline -- actions: (export if
  # @rows.any?) -- so a false condition has to render nothing at all rather
  # than an empty container the row still has to space around.
  # Every control in the row is a 36px touch target, and the size is what
  # carries it: accessibility.css floors .btn-sm at 36px, so a btn-sm button is
  # already at the floor and a hand-written min-h-9 beside it asserts nothing.
  # What a call site can still get wrong is the size, which is what this pins.
  test "the clear-all link and an export action are both floored btn-sm" do
    render inline: <<~ERB
      <%= filter_bar chips: [{ label: "Status: Active", url: "/slots?a=1" }],
                     clear_url: "/slots",
                     actions: export_csv_link("/slots.csv") do %>
        <p>Panel form</p>
      <% end %>
    ERB

    assert_select "a.btn-sm", text: "Clear All Filters"
    assert_select "div.ms-auto a.btn-sm", text: /Export CSV/
  end

  test "renders no action container when the actions are blank" do
    render inline: <<~ERB
      <%= filter_bar actions: (button_link("Export CSV", :secondary, "/x.csv") if false) do %>
        <p>Panel form</p>
      <% end %>
    ERB

    assert_select "div.ms-auto", count: 0
    assert_select "a", count: 0
  end

  test "filter_chips builds one chip per active filter with that filter dropped from the URL" do
    chips = filter_chips({ day: "2026-08-26", active: "active" }, { day: "Day", active: "Status" },
                         value_label: ->(key, value) { key == :active ? value.capitalize : value }) do |remaining, key|
      "/slots?#{remaining.to_query}&dropped=#{key}"
    end

    assert_equal [
      { label: "Day: 2026-08-26", url: "/slots?active=active&dropped=day" },
      { label: "Status: Active", url: "/slots?day=2026-08-26&dropped=active" }
    ], chips
  end

  # The contract two Quartermaster pages depend on: All first, then commonest
  # status first with ties broken by name, each labelled "status (count)". The
  # status reads as it is stored -- nothing re-cases it.
  test "filter_time reads a whole date with a four-digit year, and refuses what it would have to guess" do
    assert_equal Time.zone.local(2026, 10, 25), UiComponents::FilterBarHelper.filter_time("2026-10-25")
    assert_equal Time.zone.local(2026, 10, 25, 14, 30), UiComponents::FilterBarHelper.filter_time("2026-10-25T14:30")
    # A partial date, a two-digit year, a day the month lacks, a five-digit year.
    ["26", "Oct 25 26", "26-10-25", "2026-02-30", "2026-02-29", "99999-01-01", "not a date", "", nil].each do |value|
      assert_nil UiComponents::FilterBarHelper.filter_time(value), value.inspect
    end
  end

  test "filter_status_options offers All, then the statuses held, commonest first" do
    options = filter_status_options({ "active" => 2, "retired" => 9, "inactive" => 2 })

    assert_equal [["All", "all"], ["retired (9)", "retired"],
                  ["active (2)", "active"], ["inactive (2)", "inactive"]], options
  end

  test "filter_status_options offers only All when nothing holds a status" do
    assert_equal [["All", "all"]], filter_status_options({})
  end

  # A select navigates, so its counts have to promise what the choice delivers.
  # Ordering still comes from the full counts, so the options do not reshuffle
  # as the page's other filters change, and a status narrowed to no one is
  # still offered rather than dropped.
  test "filter_status_options labels with matching counts but orders by the full ones" do
    options = filter_status_options({ "active" => 2, "retired" => 9 },
                                    matching: { "active" => 2 })

    assert_equal [["All", "all"], ["retired (0)", "retired"], ["active (2)", "active"]], options
  end

  test "filter_signed_up_options is the tri-state the concern accepts" do
    assert_equal [["All", "all"], ["Yes", SignedUpFilterConcern::SIGNED_UP_YES],
                  ["No", SignedUpFilterConcern::SIGNED_UP_NO]], filter_signed_up_options
  end
end
