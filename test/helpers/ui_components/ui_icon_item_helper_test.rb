# frozen_string_literal: true

require "test_helper"

class UiIconItemHelperTest < ActionView::TestCase
  include UiComponents::UiIconItemHelper
  include IconHelper

  test "renders the icon beside the block, offset onto the first line" do
    render inline: <<~ERB
      <%= ui_icon_item "circle-check", :regular do %>
        Verify your entries
      <% end %>
    ERB

    assert_select "li.flex.items-start.gap-2" do
      assert_select "i.fa-regular.fa-circle-check.mt-0\\.5.shrink-0"
      assert_select "span", text: /Verify your entries/
    end
  end

  test "a tone is a whole class name on the icon, and the default is none" do
    render inline: <<~ERB
      <%= ui_icon_item("circle-xmark", :solid, tone: "icon-error") { "Cannot be sold" } %>
      <%= ui_icon_item("envelope", :solid) { "Contact Ranger Ticketing" } %>
    ERB

    assert_select "i.fa-circle-xmark.icon-error"
    assert_select "i.fa-envelope"
    assert_select "i.fa-envelope.icon-error", count: 0
  end

  test "the block may carry markup, not just text" do
    render inline: <<~ERB
      <%= ui_icon_item "clock", :regular do %>
        <strong>Wait</strong> for a correction request
      <% end %>
    ERB

    assert_select "li span strong", text: "Wait"
  end
end
