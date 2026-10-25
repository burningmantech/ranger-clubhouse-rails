# frozen_string_literal: true

require "test_helper"

class UiDisclosureHelperTest < ActionView::TestCase
  include UiComponents::UiDisclosureHelper
  include IconHelper

  test "ui_disclosure renders bare inline markup by default" do
    render inline: <<~ERB
      <%= ui_disclosure "Rejection message" do %>
        <p>Sorry, those handles are taken.</p>
      <% end %>
    ERB

    assert_select "details", count: 1
    assert_select "details[open]", count: 0
    # min-h-9 is the 36px touch floor, built in so no call site has to add it.
    assert_select "details > summary.cursor-pointer.min-h-9.py-2", text: "Rejection message"
    assert_select "details > div > p", text: "Sorry, those handles are taken."
    # The native marker is the only expand affordance on inline disclosures, and
    # only display: list-item draws it -- flex would drop it.
    assert_no_match "list-none", rendered
    assert_select "summary.flex, summary.inline-flex", count: 0
  end

  test "ui_disclosure inline supports custom classes and attributes" do
    render inline: <<~ERB
      <%= ui_disclosure "Rank change history (2)",
                        open: true,
                        class: "mt-3",
                        summary_class: "text-stone-muted",
                        content_class: "mt-2",
                        data: { testid: "disclosure" },
                        summary_html: { id: "custom-summary" },
                        content_html: { id: "custom-content" } do %>
        History list
      <% end %>
    ERB

    assert_select "details.mt-3[open][data-testid='disclosure']", count: 1
    assert_select "summary#custom-summary.cursor-pointer.text-stone-muted",
                  text: "Rank change history (2)"
    assert_select "div#custom-content.mt-2", text: "History list"
  end

  test "ui_disclosure card renders the boxed pattern with a bold plain title" do
    render inline: <<~ERB
      <%= ui_disclosure "Event categories", variant: :card, subtitle: "3 selected" do %>
        Checkbox grid
      <% end %>
    ERB

    assert_select "div.rounded-base.border.border-line > details.group", count: 1
    # The hook components/disclosure.css needs to leave a closed card off paper.
    assert_select "div.disclosure-card > details.group", count: 1
    assert_select "summary.cursor-pointer.list-none.px-4.py-3", count: 1
    assert_select "summary > div.flex.items-center.justify-between.gap-3", count: 1
    assert_select "div.text-base.text-heading.font-semibold", text: "Event categories"
    assert_select "div.text-sm.text-stone-muted", text: "3 selected"
    assert_select "span.shrink-0.text-stone-muted.transition-transform.group-open\\:rotate-180 i.fa-chevron-down",
                  count: 1
    assert_select "details > div.border-t.border-line.px-4.pb-4.pt-3", text: "Checkbox grid"
    assert_includes rendered, "[&amp;::-webkit-details-marker]:hidden"
  end

  test "ui_disclosure card leaves rich HTML summaries unbolded and skips the subtitle wrapper" do
    render inline: <<~ERB
      <%= ui_disclosure safe_join([tag.span("#123", class: "font-semibold"), " Dirt - Green Dot"]),
                        variant: :card, open: true, class: "mb-2" do %>
        Log table
      <% end %>
    ERB

    assert_select "div.rounded-base.mb-2 > details.group[open]", count: 1
    assert_select "div.text-base.text-heading", count: 1
    assert_select "div.text-base.text-heading.font-semibold", count: 0
    assert_select "div.text-base.text-heading > span.font-semibold", text: "#123"
  end

  test "ui_disclosure requires a block" do
    error = assert_raises(ArgumentError) { ui_disclosure("Summary") }
    assert_equal "ui_disclosure requires a block", error.message
  end

  test "ui_disclosure requires summary content" do
    error = assert_raises(ArgumentError) do
      ui_disclosure(nil) { "Body" }
    end

    assert_equal "ui_disclosure requires summary content", error.message
  end

  test "ui_disclosure rejects subtitle on the inline variant" do
    error = assert_raises(ArgumentError) do
      ui_disclosure("Summary", subtitle: "lost") { "Body" }
    end

    assert_equal "ui_disclosure subtitle: requires variant: :card", error.message
  end

  test "ui_disclosure rejects unknown variants" do
    error = assert_raises(ArgumentError) do
      ui_disclosure("Summary", variant: :popover) { "Body" }
    end

    assert_equal "ui_disclosure unknown variant: :popover", error.message
  end
end
