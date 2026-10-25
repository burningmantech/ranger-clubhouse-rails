# frozen_string_literal: true

require "test_helper"

class UiAccordionHelperTest < ActionView::TestCase
  include UiComponents::UiAccordionHelper

  test "ui_accordion renders the default collapse markup" do
    default_summary_selector = [
      "details > summary.collapse-title.flex.items-center.min-h-9.px-0.py-2.pr-10",
      "text-left.text-sm.font-semibold.text-heading"
    ].join(".")

    render inline: <<~ERB
      <%= ui_accordion "Positions (3 positions)" do %>
        <div class="grid grid-cols-2">Accordion body</div>
      <% end %>
    ERB

    assert_select "details.collapse.collapse-arrow.rounded-none.border-0.bg-transparent", count: 1
    assert_select(
      default_summary_selector,
      text: "Positions (3 positions)"
    )
    assert_select(
      "details > div.collapse-content.px-0.pt-2 .grid.grid-cols-2",
      text: "Accordion body"
    )
  end

  test "ui_accordion supports custom and unstyled rendering" do
    render inline: <<~ERB
      <%= ui_accordion "<strong>Need help?</strong>".html_safe,
                       unstyled: true,
                       open: true,
                       class: "mt-3",
                       summary_class: "cursor-pointer text-sm font-medium",
                       content_class: "mt-2 text-sm",
                       data: { testid: "accordion" },
                       summary_html: { id: "custom-summary" },
                       content_html: { id: "custom-content" } do %>
        Someone texted STOP.
      <% end %>
    ERB

    assert_select "details.mt-3[open][data-testid='accordion']", count: 1
    assert_select "details.collapse", count: 0
    assert_select "summary#custom-summary.cursor-pointer.text-sm.font-medium" do
      assert_select "strong", text: "Need help?"
    end
    assert_select "div#custom-content.mt-2.text-sm", text: "Someone texted STOP."
  end

  test "ui_accordion requires a block" do
    error = assert_raises(ArgumentError) { ui_accordion("Summary") }
    assert_equal "ui_accordion requires a block", error.message
  end

  test "ui_accordion requires summary content" do
    error = assert_raises(ArgumentError) do
      ui_accordion(nil) { "Accordion body" }
    end

    assert_equal "ui_accordion requires summary content", error.message
  end
end
