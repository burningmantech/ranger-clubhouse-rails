# frozen_string_literal: true

require "test_helper"

class UiSubheadingHelperTest < ActionView::TestCase
  include UiComponents::UiSectionHelper

  test "renders an h3 from a string" do
    render inline: '<%= ui_subheading "April" %>'

    assert_select "h3.heading-title.text-heading", text: "April", count: 1
  end

  test "renders the block beside nothing else" do
    render inline: <<~ERB
      <%= ui_subheading do %>
        Flagged <span>3</span>
      <% end %>
    ERB

    assert_select "h3", text: /Flagged\s+3/, count: 1
    assert_select "h3 span", text: "3"
  end
end
